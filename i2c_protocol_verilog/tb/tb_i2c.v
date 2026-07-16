// =============================================================================
// Proyecto: Banco de Pruebas I2C (I2C Testbench)
// Archivo:   tb_i2c.v
// Lenguaje:  Verilog-2001
// Descripción:
//   Simula y verifica la comunicación entre el controlador Maestro I2C
//   y la memoria EEPROM esclava. Realiza operaciones de escritura en un
//   registro de la memoria, y luego lee para verificar la integridad del dato.
// =============================================================================

`timescale 1ns/1ps

module tb_i2c;

    // Parámetros del reloj de sistema
    localparam CLK_PERIOD = 20; // 50 MHz (20ns por ciclo)
    
    // Señales de Testbench
    reg clk;
    reg rst_n;
    
    // Interfaz de Usuario del Maestro
    reg [6:0] addr;
    reg       rnw;
    reg [7:0] wdata;
    reg [1:0] cmd;
    reg       cmd_valid;
    reg       last_byte;
    
    wire [7:0] rdata;
    wire       cmd_ready;
    wire       ack_err;
    wire       busy;
    
    // Líneas Físicas I2C
    wire sda;
    wire scl;
    
    // Resistencias Pull-Up en el Bus I2C (Primitiva Verilog)
    pullup (sda);
    pullup (scl);

    // Bloque de monitoreo para depuración
    initial begin
        $monitor("Time=%0d ns | SDA=%b SCL=%b | M_State=%h S_State=%h | cmd_valid=%b cmd_ready=%b busy=%b bus_active=%b | RegAddr=%h S_Shift=%b", 
                 $time, sda, scl, u_master.state, u_slave.state, cmd_valid, cmd_ready, busy, u_master.bus_active, u_slave.reg_addr, u_slave.shift_reg);
    end

    // Instancia del Controlador Maestro I2C
    i2c_master #(
        .CLK_DIV(25) // Valor menor para acelerar la simulación en testbench
                     // 50MHz / (4 * 500kHz SCL) = 25
    ) u_master (
        .clk(clk),
        .rst_n(rst_n),
        .addr(addr),
        .rnw(rnw),
        .wdata(wdata),
        .cmd(cmd),
        .cmd_valid(cmd_valid),
        .last_byte(last_byte),
        .rdata(rdata),
        .cmd_ready(cmd_ready),
        .ack_err(ack_err),
        .busy(busy),
        .sda(sda),
        .scl(scl)
    );

    // Instancia del Dispositivo Esclavo I2C (EEPROM 24C02)
    i2c_slave #(
        .SLAVE_ADDR(7'h50) // Dirección 7'h50 (EEPROM estándar)
    ) u_slave (
        .clk(clk),
        .rst_n(rst_n),
        .sda(sda),
        .scl(scl)
    );

    // Generador de Reloj del Sistema
    always begin
        #(CLK_PERIOD/2) clk = ~clk;
    end

    // Tarea para enviar comandos al Maestro de manera estructurada
    task send_i2c_cmd(
        input [1:0] i_cmd,
        input [6:0] i_addr,
        input       i_rnw,
        input [7:0] i_wdata,
        input       i_last_byte
    );
    begin
        // Esperar a que el maestro esté listo
        while (!cmd_ready) @(posedge clk);
        
        // Sincronizar al flanco de bajada del reloj
        @(negedge clk);
        
        // Aplicar entradas de manera síncrona en flanco de bajada
        cmd       = i_cmd;
        addr      = i_addr;
        rnw       = i_rnw;
        wdata     = i_wdata;
        last_byte = i_last_byte;
        cmd_valid = 1'b1;
        
        // Mantener activo por un ciclo de reloj
        @(negedge clk);
        cmd_valid = 1'b0;
        
        // Esperar a que la operación empiece y termine (en flanco de subida)
        @(posedge clk);
        while (busy || !cmd_ready) @(posedge clk);
        
        // Espera corta síncrona entre comandos (ej. 2 ciclos)
        repeat (2) @(posedge clk);
    end
    endtask

    // Bloque Principal de Simulación
    initial begin
        // Inicialización de señales
        clk       = 0;
        rst_n     = 0;
        addr      = 0;
        rnw       = 0;
        wdata     = 0;
        cmd       = 0;
        cmd_valid = 0;
        last_byte = 0;
        
        // Configurar archivos VCD para guardar ondas de simulación
        $dumpfile("sim/i2c_simulation.vcd");
        $dumpvars(0, tb_i2c);
        
        $display("[I2C Testbench] Iniciando simulación...");
        
        // Aplicar Reset
        #100;
        rst_n = 1;
        #200;
        
        // ----------------------------------------------------
        // PRUEBA 1: ESCRITURA EN REGISTRO DE EEPROM (Single Write)
        // Escribir el dato 8'hA5 en el registro 8'h20 del esclavo 7'h50
        // ----------------------------------------------------
        $display("\n--- Iniciando Transacción 1: Escritura (Write 8'hA5 a Reg 8'h20) ---");
        
        // 1. Enviar Condición de START + Dirección del Esclavo en Escritura (rnw = 0)
        send_i2c_cmd(2'b00, 7'h50, 1'b0, 8'h00, 1'b0);
        if (ack_err) $display("[ERROR] NACK recibido al enviar dirección para escritura!");
        else $display("[OK] Dirección 7'h50 enviada correctamente (ACK recibido).");
        
        // 2. Enviar la Dirección del Registro (Word Address = 8'h20)
        send_i2c_cmd(2'b01, 7'h50, 1'b0, 8'h20, 1'b0);
        if (ack_err) $display("[ERROR] NACK recibido al enviar registro!");
        else $display("[OK] Dirección de registro 8'h20 enviada correctamente.");
        
        // 3. Enviar el Dato a Escribir (wdata = 8'hA5)
        send_i2c_cmd(2'b01, 7'h50, 1'b0, 8'hA5, 1'b0);
        if (ack_err) $display("[ERROR] NACK recibido al enviar dato!");
        else $display("[OK] Dato 8'hA5 enviado correctamente.");
        
        // 4. Enviar Condición de STOP
        send_i2c_cmd(2'b11, 7'h50, 1'b0, 8'h00, 1'b0);
        $display("[OK] Condición STOP generada. Escritura finalizada.");
        
        #1000; // Simular tiempo de escritura interno de la EEPROM
        
        // ----------------------------------------------------
        // PRUEBA 2: LECTURA EN REGISTRO DE EEPROM (Random Read)
        // Leer el dato del registro 8'h20 de la EEPROM 7'h50
        // Para esto se hace: START(W) -> RegAddr -> RepSTART(R) -> ReadByte -> STOP
        // ----------------------------------------------------
        $display("\n--- Iniciando Transacción 2: Lectura Aleatoria (Random Read de Reg 8'h20) ---");
        
        // 1. START con Dirección de esclavo en Escritura (para configurar el puntero del registro)
        send_i2c_cmd(2'b00, 7'h50, 1'b0, 8'h00, 1'b0);
        if (ack_err) $display("[ERROR] NACK recibido en START para lectura!");
        
        // 2. Enviar Dirección del Registro (Word Address = 8'h20)
        send_i2c_cmd(2'b01, 7'h50, 1'b0, 8'h20, 1'b0);
        if (ack_err) $display("[ERROR] NACK recibido al configurar registro de lectura!");
        
        // 3. Repeated START con Dirección del Esclavo en Modo LECTURA (rnw = 1)
        send_i2c_cmd(2'b00, 7'h50, 1'b1, 8'h00, 1'b0);
        if (ack_err) $display("[ERROR] NACK recibido en Repeated START para lectura!");
        else $display("[OK] RepSTART enviado. Dirección 7'h50 en modo lectura correcta.");
        
        // 4. Leer Dato de la EEPROM (Enviar NACK al final porque es el último byte)
        send_i2c_cmd(2'b10, 7'h50, 1'b1, 8'h00, 1'b1);
        $display("[OK] Byte leido de la EEPROM: 8'h%h", rdata);
        
        // 5. Enviar Condición de STOP
        send_i2c_cmd(2'b11, 7'h50, 1'b1, 8'h00, 1'b0);
        $display("[OK] Condición STOP generada. Lectura finalizada.");
        
        // ----------------------------------------------------
        // VERIFICACIÓN
        // ----------------------------------------------------
        $display("\n=== Resultados de Verificación ===");
        if (rdata === 8'hA5) begin
            $display("[SUCCESFUL] TEST PASSED: El dato leido (8'h%h) coincide con el dato escrito (8'hA5).", rdata);
        end else begin
            $display("[FAILED] TEST FAILED: Se esperaba 8'hA5 pero se leyó 8'h%h.", rdata);
        end
        
        $display("\n[I2C Testbench] Simulación completada exitosamente.");
        $finish;
    end

endmodule
