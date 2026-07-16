Protocolo I2C en Verilog (Maestro y Esclavo)
Descripción

En este proyecto se implementó el protocolo I2C utilizando Verilog. El diseño está compuesto por un módulo maestro y un módulo esclavo que simula una memoria EEPROM. La idea fue desarrollar la comunicación entre ambos dispositivos y comprobar mediante simulación que el intercambio de datos se realiza correctamente.
## Estructura del Proyecto

El repositorio está organizado de la siguiente manera:

```text
├── src/
│   ├── i2c_master.v   # Controlador Maestro I2C estructurado por comandos
│   └── i2c_slave.v    # Modelo de Esclavo EEPROM 24C02 (256 bytes)
├── tb/
│   └── tb_i2c.v       # Banco de pruebas (Testbench) autocontenido
└── sim/
    ├── sim.log        # Log de salida de la última simulación
    └── i2c_simulation.vcd  # Formato de ondas VCD para análisis
```

---
Carpeta src

Aquí está el código principal del proyecto.

i2c_master.v: contiene el módulo maestro, encargado de iniciar la comunicación y controlar el envío y la recepción de los datos.
i2c_slave.v: contiene el módulo esclavo, que responde a las peticiones del maestro y almacena la información en una memoria.
Carpeta tb

En esta carpeta está el banco de pruebas utilizado para verificar el funcionamiento del diseño antes de implementarlo.

Carpeta sim

Aquí se guardan los archivos generados durante la simulación, como el registro de ejecución y las formas de onda.

Funcionamiento

El funcionamiento del proyecto consiste en que el maestro inicia la comunicación con el esclavo, envía la dirección de memoria y posteriormente escribe o lee un dato según la operación que se quiera realizar. Todo el proceso se controla mediante una máquina de estados que organiza cada una de las etapas de la comunicación.

Por su parte, el esclavo recibe las solicitudes del maestro, guarda los datos cuando se realiza una escritura y entrega la información almacenada cuando se solicita una lectura.

Máquina de estados

El módulo maestro trabaja con una máquina de estados sencilla que permite controlar cada paso de la comunicación.

Los estados principales son:

Espera de un nuevo comando.
Inicio de la comunicación.
Envío de datos.
Recepción de datos.
Verificación de la respuesta del esclavo.
Finalización de la comunicación.

Esta organización ayuda a que el diseño sea más claro y facilita su simulación.

Simulación

Para comprobar el funcionamiento del proyecto se utilizó Icarus Verilog junto con GTKWave.

La simulación consistió en escribir un dato dentro de la memoria del esclavo y después leerlo nuevamente para verificar que el valor obtenido fuera el mismo.

Los comandos utilizados fueron:

mkdir -p sim

iverilog -o sim/i2c_sim src/i2c_master.v src/i2c_slave.v tb/tb_i2c.v

vvp sim/i2c_sim

Para visualizar las señales se utilizó:

gtkwave sim/i2c_simulation.vcd
Prueba realizada

Durante las pruebas se escribió el dato A5 en una posición de memoria y posteriormente se realizó una lectura de esa misma dirección.

Al finalizar la simulación se comprobó que el dato leído coincidía con el dato que había sido escrito, indicando que la comunicación entre el maestro y el esclavo funcionó correctamente.

Señales principales
Señal	Función
clk	Reloj del sistema.
rst_n	Reinicia el circuito.
addr	Dirección del esclavo.
rnw	Selecciona lectura o escritura.
wdata	Dato que se envía al esclavo.
cmd	Indica la operación que debe realizar el maestro.
cmd_valid	Habilita el comando.
last_byte	Indica el último dato durante una lectura.
rdata	Dato recibido desde el esclavo.
cmd_ready	Indica que el maestro está listo para recibir otro comando.
ack_err	Señala si hubo un error durante la comunicación.
busy	Indica que el módulo está ocupado.
sda	Línea de datos del bus I2C.
scl	Línea de reloj del bus I2C.
