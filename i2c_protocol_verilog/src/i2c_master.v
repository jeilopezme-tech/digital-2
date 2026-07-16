// =============================================================================
// Proyecto: Controlador Maestro I2C (I2C Master Controller)
// Archivo:   i2c_master.v
// Lenguaje:  Verilog-2001
// Descripción:
//   Implementa un controlador Maestro I2C robusto con soporte para Clock
//   Stretching, direccionamiento de 7 bits, y máquina de estados estructurada
//   basada en comandos. Ideal para comunicación con EEPROMs y sensores.
// =============================================================================

module i2c_master #(
    parameter CLK_DIV = 125 // Divisor para generar 4x la frecuencia de SCL.
                            // Fscl_clk_en = Fclk / CLK_DIV
                            // Ej: Para clk = 50MHz, SCL = 100kHz (4x = 400kHz):
                            // CLK_DIV = 50,000,000 / 400,000 = 125.
)(
    input  wire        clk,        // Reloj del sistema (ej. 50 MHz)
    input  wire        rst_n,      // Reset activo en bajo, asíncrono
    
    // Interfaz de Usuario / Microcontrolador
    input  wire [6:0]  addr,       // Dirección de 7 bits del dispositivo esclavo
    input  wire        rnw,        // Read/Not-Write (1: Leer, 0: Escribir)
    input  wire [7:0]  wdata,      // Dato a escribir (8 bits)
    input  wire [1:0]  cmd,        // Comando: 2'b00: START, 2'b01: WRITE, 2'b10: READ, 2'b11: STOP
    input  wire        cmd_valid,  // Señal de comando válido (inicia transacción)
    input  wire        last_byte,  // 1: Último byte leído (envía NACK), 0: Envía ACK
    
    output reg  [7:0]  rdata,      // Dato leído (8 bits)
    output reg         cmd_ready,  // Listo para recibir un nuevo comando
    output reg         ack_err,    // Error de ACK (1: NACK recibido, 0: ACK correcto)
    output reg         busy,       // Maestro ocupado realizando transferencia
    
    // Interfaz Física I2C (Pines Bidireccionales)
    inout  wire        sda,
    inout  wire        scl
);

    // Codificación de Comandos
    localparam CMD_START = 2'b00;
    localparam CMD_WRITE = 2'b01;
    localparam CMD_READ  = 2'b10;
    localparam CMD_STOP  = 2'b11;

    // Estados de la FSM Principal
    localparam STATE_IDLE      = 4'h0;
    localparam STATE_START     = 4'h1;
    localparam STATE_ADDR      = 4'h2;
    localparam STATE_ACK_ADDR  = 4'h3;
    localparam STATE_WRITE     = 4'h4;
    localparam STATE_ACK_WRITE = 4'h5;
    localparam STATE_READ      = 4'h6;
    localparam STATE_ACK_READ  = 4'h7;
    localparam STATE_STOP      = 4'h8;

    // FSM Estados
    reg [3:0] state, next_state;
    
    // Sub-fase interna para cada bit (4 fases por bit de SCL)
    // F0: SCL=0, SDA cambia
    // F1: SCL=1 (comienzo del semiciclo alto)
    // F2: SCL=1 (muestreo estable)
    // F3: SCL=0 (comienzo del semiciclo bajo, hold)
    reg [1:0] phase_cnt;
    
    // Contador de bits (para dirección o dato)
    reg [2:0] bit_cnt;
    
    // Registros temporales para bus bidireccional
    reg sda_out;
    reg scl_out;
    
    // Buffer del bus I2C (Salida Open-Drain)
    assign sda = sda_out ? 1'bz : 1'b0;
    assign scl = scl_out ? 1'bz : 1'b0;
    
    // Lectura de pines físicos para entrada
    wire sda_in = sda;
    wire scl_in = scl;

    // Divisor de Reloj Interno (Genera habilitación de fase)
    reg [15:0] clk_cnt;
    wire phase_tick;
    
    // Soporte de Clock Stretching: 
    // Si queremos SCL=1 (scl_out=1) pero scl_in es 0 (el esclavo retiene SCL en bajo),
    // detenemos el contador de reloj para pausar la FSM del maestro.
    wire scl_stretched = (scl_out == 1'b1) && (scl_in == 1'b0);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 16'd0;
        end else if (busy && !scl_stretched) begin
            if (clk_cnt >= CLK_DIV - 1)
                clk_cnt <= 16'd0;
            else
                clk_cnt <= clk_cnt + 1'b1;
        end else if (!busy) begin
            clk_cnt <= 16'd0;
        end
    end
    
    assign phase_tick = (busy && !scl_stretched) ? (clk_cnt == CLK_DIV - 1) : 1'b0;

    // Registro de comandos e información latcheada
    reg [6:0] r_addr;
    reg       r_rnw;
    reg [7:0] r_wdata;
    reg       r_last_byte;
    
    // Bandera para indicar que hay una transacción activa en el bus
    reg       bus_active;

    // Máquina de Estados de Control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= STATE_IDLE;
            phase_cnt   <= 2'b00;
            bit_cnt     <= 3'd0;
            sda_out     <= 1'b1;
            scl_out     <= 1'b1;
            cmd_ready   <= 1'b1;
            busy        <= 1'b0;
            ack_err     <= 1'b0;
            rdata       <= 8'd0;
            r_addr      <= 7'd0;
            r_rnw       <= 1'b0;
            r_wdata     <= 8'd0;
            r_last_byte <= 1'b0;
            bus_active  <= 1'b0;
        end else begin
            case (state)
                
                STATE_IDLE: begin
                    cmd_ready  <= 1'b1;
                    busy       <= 1'b0;
                    sda_out    <= 1'b1;
                    // Mantener SCL en bajo si la transacción está activa (evita falsos STOPs y STARTs)
                    scl_out    <= bus_active ? 1'b0 : 1'b1;
                    phase_cnt  <= 2'b00;
                    bit_cnt    <= 3'd7;
                    if (cmd_valid && cmd_ready) begin
                        cmd_ready <= 1'b0;
                        busy      <= 1'b1;
                        r_addr    <= addr;
                        r_rnw     <= rnw;
                        r_wdata   <= wdata;
                        r_last_byte <= last_byte;
                        
                        case (cmd)
                            CMD_START: begin
                                state      <= STATE_START;
                                bus_active <= 1'b1;
                            end
                            CMD_WRITE: state <= STATE_WRITE;
                            CMD_READ:  state <= STATE_READ;
                            CMD_STOP: begin
                                state      <= STATE_STOP;
                                bus_active <= 1'b0;
                            end
                            default:   state <= STATE_IDLE;
                        endcase
                    end
                end

                STATE_START: begin
                    if (phase_tick) begin
                        phase_cnt <= phase_cnt + 1'b1;
                        case (phase_cnt)
                            2'b00: begin // F0: SCL=0, SDA=1 (Liberar SDA con SCL en bajo)
                                sda_out <= 1'b1;
                                scl_out <= 1'b0;
                            end
                            2'b01: begin // F1: SCL=1, SDA=1 (Llevar SCL a alto con SDA estable en alto)
                                sda_out <= 1'b1;
                                scl_out <= 1'b1;
                            end
                            2'b10: begin // F2: SCL=1, SDA=0 (Generar flanco de bajada de SDA -> START)
                                sda_out <= 1'b0;
                                scl_out <= 1'b1;
                            end
                            2'b11: begin // F3: SCL=0, SDA=0 (Llevar SCL a bajo)
                                sda_out <= 1'b0;
                                scl_out <= 1'b0;
                                // Ir a transmitir dirección
                                bit_cnt <= 3'd7;
                                state   <= STATE_ADDR;
                            end
                        endcase
                    end
                end

                STATE_ADDR: begin
                    if (phase_tick) begin
                        phase_cnt <= phase_cnt + 1'b1;
                        case (phase_cnt)
                            2'b00: begin // F0: SCL=0, SDA cambia al bit de la dirección
                                scl_out <= 1'b0;
                                if (bit_cnt > 0)
                                    sda_out <= r_addr[bit_cnt - 1]; // Dirección bits [6:0]
                                else
                                    sda_out <= r_rnw; // Bit R/W al final (bit_cnt = 0)
                            end
                            2'b01: begin // F1: SCL=1
                                scl_out <= 1'b1;
                            end
                            2'b10: begin // F2: SCL=1 (estable)
                                scl_out <= 1'b1;
                            end
                            2'b11: begin // F3: SCL=0 (hold)
                                scl_out <= 1'b0;
                                if (bit_cnt == 0) begin
                                    state <= STATE_ACK_ADDR;
                                end else begin
                                    bit_cnt <= bit_cnt - 1'b1;
                                end
                            end
                        endcase
                    end
                end

                STATE_ACK_ADDR: begin
                    if (phase_tick) begin
                        phase_cnt <= phase_cnt + 1'b1;
                        case (phase_cnt)
                            2'b00: begin // F0: liberar SDA
                                sda_out <= 1'b1;
                                scl_out <= 1'b0;
                            end
                            2'b01: begin // F1: SCL=1
                                scl_out <= 1'b1;
                            end
                            2'b10: begin // F2: Muestrear ACK del esclavo (SDA debe ser 0)
                                scl_out <= 1'b1;
                                ack_err <= sda_in; // 0 = ACK, 1 = NACK (Error)
                            end
                            2'b11: begin // F3: SCL=0
                                scl_out <= 1'b0;
                                state   <= STATE_IDLE; // Finaliza el comando START
                            end
                        endcase
                    end
                end

                STATE_WRITE: begin
                    if (phase_tick) begin
                        phase_cnt <= phase_cnt + 1'b1;
                        case (phase_cnt)
                            2'b00: begin // F0: SCL=0, SDA cambia
                                scl_out <= 1'b0;
                                sda_out <= r_wdata[bit_cnt];
                            end
                            2'b01: begin // F1: SCL=1
                                scl_out <= 1'b1;
                            end
                            2'b10: begin // F2: SCL=1 (estable)
                                scl_out <= 1'b1;
                            end
                            2'b11: begin // F3: SCL=0 (hold)
                                scl_out <= 1'b0;
                                if (bit_cnt == 0) begin
                                    state <= STATE_ACK_WRITE;
                                end else begin
                                    bit_cnt <= bit_cnt - 1'b1;
                                end
                            end
                        endcase
                    end
                end

                STATE_ACK_WRITE: begin
                    if (phase_tick) begin
                        phase_cnt <= phase_cnt + 1'b1;
                        case (phase_cnt)
                            2'b00: begin // F0: liberar SDA
                                sda_out <= 1'b1;
                                scl_out <= 1'b0;
                            end
                            2'b01: begin // F1: SCL=1
                                scl_out <= 1'b1;
                            end
                            2'b10: begin // F2: Muestrear ACK del esclavo
                                scl_out <= 1'b1;
                                ack_err <= sda_in;
                            end
                            2'b11: begin // F3: SCL=0
                                scl_out <= 1'b0;
                                state   <= STATE_IDLE; // Finaliza el comando WRITE
                            end
                        endcase
                    end
                end

                STATE_READ: begin
                    if (phase_tick) begin
                        phase_cnt <= phase_cnt + 1'b1;
                        case (phase_cnt)
                            2'b00: begin // F0: liberar SDA para lectura
                                sda_out <= 1'b1;
                                scl_out <= 1'b0;
                            end
                            2'b01: begin // F1: SCL=1
                                scl_out <= 1'b1;
                            end
                            2'b10: begin // F2: Muestrear dato del esclavo
                                scl_out <= 1'b1;
                                rdata[bit_cnt] <= sda_in;
                            end
                            2'b11: begin // F3: SCL=0
                                scl_out <= 1'b0;
                                if (bit_cnt == 0) begin
                                    state <= STATE_ACK_READ;
                                end else begin
                                    bit_cnt <= bit_cnt - 1'b1;
                                end
                            end
                        endcase
                    end
                end

                STATE_ACK_READ: begin
                    if (phase_tick) begin
                        phase_cnt <= phase_cnt + 1'b1;
                        case (phase_cnt)
                            2'b00: begin // F0: enviar ACK (0) o NACK (1)
                                scl_out <= 1'b0;
                                sda_out <= r_last_byte; // NACK si es el último byte
                            end
                            2'b01: begin // F1: SCL=1
                                scl_out <= 1'b1;
                            end
                            2'b10: begin // F2: mantener estable
                                scl_out <= 1'b1;
                            end
                            2'b11: begin // F3: SCL=0, liberar SDA
                                scl_out <= 1'b0;
                                sda_out <= 1'b1;
                                state   <= STATE_IDLE; // Finaliza el comando READ
                            end
                        endcase
                    end
                end

                STATE_STOP: begin
                    if (phase_tick) begin
                        phase_cnt <= phase_cnt + 1'b1;
                        case (phase_cnt)
                            2'b00: begin // F0: SCL=0, SDA=0
                                sda_out <= 1'b0;
                                scl_out <= 1'b0;
                            end
                            2'b01: begin // F1: SCL=1, SDA=0
                                sda_out <= 1'b0;
                                scl_out <= 1'b1;
                            end
                            2'b10: begin // F2: SCL=1, liberar SDA (crea flanco de subida -> STOP)
                                sda_out <= 1'b1;
                                scl_out <= 1'b1;
                            end
                            2'b11: begin // F3: SCL=1, SDA=1
                                sda_out <= 1'b1;
                                scl_out <= 1'b1;
                                state   <= STATE_IDLE; // Finaliza la transferencia
                            end
                        endcase
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
