// =============================================================================
// Proyecto: Modelo de Esclavo I2C (I2C Slave - EEPROM 24C02)
// Archivo:   i2c_slave.v
// Lenguaje:  Verilog-2001
// Descripción:
//   Implementa un dispositivo esclavo I2C que emula una memoria EEPROM de 256
//   bytes con la dirección base 7'h50. Soporta operaciones de escritura simple,
//   escritura secuencial, lectura aleatoria y lectura secuencial.
//   Maneja detección de START/STOP de forma síncrona con el reloj del sistema.
// =============================================================================

module i2c_slave #(
    parameter SLAVE_ADDR = 7'h50 // Dirección I2C predeterminada de la EEPROM
)(
    input  wire        clk,      // Reloj del sistema (sincronización de flancos)
    input  wire        rst_n,    // Reset activo en bajo, asíncrono
    
    // Pines Físicos I2C
    inout  wire        sda,
    inout  wire        scl
);

    // Estados de la FSM del Esclavo
    localparam STATE_IDLE         = 4'h0;
    localparam STATE_ADDR         = 4'h1;
    localparam STATE_ACK_ADDR     = 4'h2;
    localparam STATE_GET_REG_ADDR = 4'h3;
    localparam STATE_ACK_REG_ADDR = 4'h4;
    localparam STATE_WRITE_DATA   = 4'h5;
    localparam STATE_ACK_WRITE    = 4'h6;
    localparam STATE_READ_DATA    = 4'h7;
    localparam STATE_ACK_READ     = 4'h8;

    reg [3:0] state;
    
    // Memoria interna de la EEPROM (256 bytes)
    reg [7:0] memory [0:255];
    
    // Inicializar memoria con valores de prueba secuenciales
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            memory[i] = i[7:0]; // Por ejemplo, dirección 0x00 contiene 0x00, 0x10 contiene 0x10, etc.
        end
    end

    // Registro de desplazamiento y contadores
    reg [7:0] shift_reg;
    reg [3:0] bit_cnt;
    reg [7:0] reg_addr;     // Puntero de dirección de memoria interna
    reg       rnw;          // Operación actual (1: Leer, 0: Escribir)
    reg       sda_out;      // Registro para controlar la salida de SDA
    
    // Pin SDA como Open-Drain
    assign sda = sda_out ? 1'bz : 1'b0;
    
    // Entradas físicas
    wire sda_in = sda;
    wire scl_in = scl;

    // Sincronizadores para el bus I2C para evitar metaestabilidad
    reg sda_r1, sda_r2;
    reg scl_r1, scl_r2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_r1 <= 1'b1;
            sda_r2 <= 1'b1;
            scl_r1 <= 1'b1;
            scl_r2 <= 1'b1;
        end else begin
            sda_r1 <= sda_in;
            sda_r2 <= sda_r1;
            scl_r1 <= scl_in;
            scl_r2 <= scl_r1;
        end
    end

    // Detección de START: SDA flanco de bajada mientras SCL está en alto
    wire start_detected = (scl_r1 && scl_r2) && (sda_r2 && !sda_r1);
    
    // Detección de STOP: SDA flanco de subida mientras SCL está en alto
    wire stop_detected = (scl_r1 && scl_r2) && (!sda_r2 && sda_r1);
    
    // Detección de flancos en SCL
    wire scl_posedge = (!scl_r2 && scl_r1);
    wire scl_negedge = (scl_r2 && !scl_r1);

    // FSM Principal
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= STATE_IDLE;
            shift_reg   <= 8'd0;
            bit_cnt     <= 4'd0;
            reg_addr    <= 8'd0;
            rnw         <= 1'b0;
            sda_out     <= 1'b1; // Liberar SDA
        end else begin
            // START y STOP anulan cualquier estado
            if (start_detected) begin
                state     <= STATE_ADDR;
                bit_cnt   <= 4'd0;
                sda_out   <= 1'b1;
            end else if (stop_detected) begin
                state     <= STATE_IDLE;
                sda_out   <= 1'b1;
            end else begin
                
                case (state)
                    
                    STATE_IDLE: begin
                        sda_out <= 1'b1;
                    end
                    
                    STATE_ADDR: begin
                        if (scl_posedge) begin
                            shift_reg <= {shift_reg[6:0], sda_r1};
                            bit_cnt   <= bit_cnt + 1'b1;
                        end else if (scl_negedge && bit_cnt == 8) begin
                            // Verificar dirección
                            if (shift_reg[7:1] == SLAVE_ADDR) begin
                                rnw     <= shift_reg[0];
                                state   <= STATE_ACK_ADDR;
                                sda_out <= 1'b0; // Generar ACK (SDA=0)
                            end else begin
                                state   <= STATE_IDLE; // No es para mí
                            end
                        end
                    end
                    
                    STATE_ACK_ADDR: begin
                        if (scl_negedge) begin
                            bit_cnt <= 4'd0;
                            if (rnw) begin
                                // Cargar y preparar el primer byte de lectura inmediatamente
                                shift_reg <= {memory[reg_addr][6:0], 1'b1};
                                sda_out   <= memory[reg_addr][7];
                                state     <= STATE_READ_DATA;
                            end else begin
                                sda_out   <= 1'b1; // Liberar SDA
                                state     <= STATE_GET_REG_ADDR;
                            end
                        end
                    end
                    
                    STATE_GET_REG_ADDR: begin
                        if (scl_posedge) begin
                            shift_reg <= {shift_reg[6:0], sda_r1};
                            bit_cnt   <= bit_cnt + 1'b1;
                        end else if (scl_negedge && bit_cnt == 8) begin
                            reg_addr <= shift_reg; // Guardar dirección de memoria
                            state    <= STATE_ACK_REG_ADDR;
                            sda_out  <= 1'b0; // ACK
                        end
                    end
                    
                    STATE_ACK_REG_ADDR: begin
                        if (scl_negedge) begin
                            sda_out <= 1'b1; // Liberar SDA
                            bit_cnt <= 4'd0;
                            state   <= STATE_WRITE_DATA;
                        end
                    end
                    
                    STATE_WRITE_DATA: begin
                        if (scl_posedge) begin
                            shift_reg <= {shift_reg[6:0], sda_r1};
                            bit_cnt   <= bit_cnt + 1'b1;
                        end else if (scl_negedge && bit_cnt == 8) begin
                            memory[reg_addr] <= shift_reg; // Escribir en memoria
                            state            <= STATE_ACK_WRITE;
                            sda_out          <= 1'b0; // ACK
                        end
                    end
                    
                    STATE_ACK_WRITE: begin
                        if (scl_negedge) begin
                            sda_out  <= 1'b1; // Liberar SDA
                            reg_addr <= reg_addr + 1'b1; // Autoincremento
                            bit_cnt  <= 4'd0;
                            state    <= STATE_WRITE_DATA; // Esperar más bytes (escritura secuencial)
                        end
                    end
                    
                    STATE_READ_DATA: begin
                        // Cambiar SDA en el flanco de bajada de SCL
                        if (scl_negedge) begin
                            sda_out   <= shift_reg[7];
                            shift_reg <= {shift_reg[6:0], 1'b1};
                        end else if (scl_posedge) begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                        
                        // Una vez transmitido el byte completo, ir a esperar ACK/NACK del maestro
                        if (bit_cnt == 8) begin
                            state <= STATE_ACK_READ;
                        end
                    end
                    
                    STATE_ACK_READ: begin
                        if (scl_negedge) begin
                            sda_out <= 1'b1; // Liberar SDA para recibir ACK
                        end else if (scl_posedge) begin
                            // Muestrear ACK del maestro
                            if (sda_r1 == 1'b0) begin // Master ACKed
                                reg_addr  <= reg_addr + 1'b1; // Autoincremento
                                shift_reg <= memory[reg_addr + 1'b1]; // Pre-cargar siguiente dato
                                bit_cnt   <= 4'd0;
                                state     <= STATE_READ_DATA;
                            end else begin // Master NACKed
                                state     <= STATE_IDLE; // Fin de lectura
                            end
                        end
                    end
                    
                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end

endmodule
