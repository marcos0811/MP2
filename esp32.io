#include <WiFi.h>
#include <HTTPClient.h>
#include <SPI.h>
#include <MFRC522.h>
#include <Keypad.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <ESP32Servo.h>

// =====================================================
// WIFI Y SERVIDOR
// =====================================================

const char* ssid = "A";
const char* password = "1450329923";

const char* servidor = "http://192.168.137.1:5000";

// =====================================================
// RC522
// =====================================================

#define SS_PIN 5
#define RST_PIN 21

MFRC522 rfid(SS_PIN, RST_PIN);

// =====================================================
// LCD
// =====================================================

LiquidCrystal_I2C lcd(0x27, 16, 2);

// =====================================================
// SERVO Y BUZZER
// =====================================================

#define SERVO_PIN 27
#define BUZZER 15

// =====================================================
// LED RGB - COMUN ANODO
// GPIO 1 = Rojo
// GPIO 2 = Verde
// GPIO 3 = Azul
// LOW = encendido, HIGH = apagado
// =====================================================

#define LED_R 1
#define LED_G 2
#define LED_B 3

// =====================================================
// MENU PRINCIPAL
// =====================================================

bool menuCD = false;

Servo servo;

const int SERVO_CERRADO = 0;
const int SERVO_ABIERTO = 90;

// =====================================================
// TECLADO 4x4
// =====================================================

const byte FILAS = 4;
const byte COLUMNAS = 4;

char teclas[FILAS][COLUMNAS] = {
  {'1', '2', '3', 'A'},
  {'4', '5', '6', 'B'},
  {'7', '8', '9', 'C'},
  {'*', '0', '#', 'D'}
};

byte pinesFilas[FILAS] = {13, 14, 32, 33};
byte pinesColumnas[COLUMNAS] = {16, 17, 4, 22};

Keypad teclado = Keypad(
  makeKeymap(teclas),
  pinesFilas,
  pinesColumnas,
  FILAS,
  COLUMNAS
);


// =====================================================
// MOSTRAR EN LCD Y SERIAL
// =====================================================

void mostrarLCD(String linea1, String linea2) {

  lcd.clear();

  lcd.setCursor(0, 0);
  lcd.print(linea1);

  lcd.setCursor(0, 1);
  lcd.print(linea2);

  Serial.println();
  Serial.println("========== LCD ==========");

  Serial.print("Linea 1: ");
  Serial.println(linea1);

  Serial.print("Linea 2: ");
  Serial.println(linea2);

  Serial.println("=========================");
}


// =====================================================
// FORMATEAR SALDO PARA EL LCD
// Evita mostrar caracteres extranos provenientes
// de la respuesta JSON del servidor.
// =====================================================

String obtenerSaldoFormateado(String respuesta, String clave) {

  int posSaldo = respuesta.indexOf("\"" + clave + "\"");

  if (posSaldo < 0) {
    return "0.00";
  }

  int inicio = respuesta.indexOf(":", posSaldo);

  if (inicio < 0) {
    return "0.00";
  }

  inicio++;

  while (
    inicio < respuesta.length() &&
    (respuesta[inicio] == ' ' || respuesta[inicio] == '"')
  ) {
    inicio++;
  }

  int fin = respuesta.indexOf(",", inicio);

  if (fin < 0) {
    fin = respuesta.indexOf("}", inicio);
  }

  if (fin < 0) {
    return "0.00";
  }

  String valor = respuesta.substring(inicio, fin);
  valor.trim();

  float saldoNumerico = valor.toFloat();

  return String(saldoNumerico, 2);
}


// =====================================================
// MENU PRINCIPAL
// =====================================================

void mostrarMenuAB() {
  menuCD = false;
  mostrarLCD(
    "A-Comprar",
    "B-Recargar"
  );
  rgbAzul();
}

void mostrarMenuCD() {
  menuCD = true;
  mostrarLCD(
    "C-Consultar",
    "D-Registrar"
  );
  rgbAzul();
}


// =====================================================
// MOSTRAR MONTO DE RECARGA
// =====================================================

void mostrarMontoRecarga(String monto) {

  lcd.clear();

  lcd.setCursor(0, 0);
  lcd.print("Monto: ");
  lcd.print(monto);

  lcd.setCursor(0, 1);
  lcd.print("# Confirmar");
}


// =====================================================
// OBTENER UID
// =====================================================

String obtenerUID() {

  String uid = "";

  for (byte i = 0; i < rfid.uid.size; i++) {

    if (rfid.uid.uidByte[i] < 0x10) {
      uid += "0";
    }

    uid += String(rfid.uid.uidByte[i], HEX);

    if (i < rfid.uid.size - 1) {
      uid += ":";
    }
  }

  uid.toUpperCase();

  return uid;
}


// =====================================================
// ESPERAR TARJETA NFC
// =====================================================

bool esperarTarjeta(String &uid) {

  Serial.println();
  Serial.println("Esperando tarjeta NFC...");

  unsigned long tiempoInicio = millis();

  while (millis() - tiempoInicio < 30000) {

    if (!rfid.PICC_IsNewCardPresent()) {
      delay(50);
      continue;
    }

    if (!rfid.PICC_ReadCardSerial()) {
      delay(50);
      continue;
    }

    uid = obtenerUID();

    Serial.print("Tarjeta detectada. UID: ");
    Serial.println(uid);

    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();

    return true;
  }

  Serial.println("Tiempo agotado esperando tarjeta.");

  return false;
}


// =====================================================
// LED RGB
// =====================================================

// Azul: sistema listo / esperando una accion o tarjeta.
// Verde: operacion aceptada/exitosamente realizada.
// Rojo: operacion rechazada, error o usuario no registrado.

void apagarRGB() {

  digitalWrite(LED_R, HIGH);
  digitalWrite(LED_G, HIGH);
  digitalWrite(LED_B, HIGH);
}


void rgbRojo() {

  digitalWrite(LED_R, LOW);
  digitalWrite(LED_G, HIGH);
  digitalWrite(LED_B, HIGH);
}


void rgbVerde() {

  digitalWrite(LED_R, HIGH);
  digitalWrite(LED_G, LOW);
  digitalWrite(LED_B, HIGH);
}


void rgbAzul() {

  digitalWrite(LED_R, HIGH);
  digitalWrite(LED_G, HIGH);
  digitalWrite(LED_B, LOW);
}


// =====================================================
// BUZZER
// =====================================================

void beep(int frecuencia, int duracion) {

  int periodo = 1000000 / frecuencia;
  int mitadPeriodo = periodo / 2;

  unsigned long tiempoInicio = millis();

  while (millis() - tiempoInicio < duracion) {

    digitalWrite(BUZZER, HIGH);
    delayMicroseconds(mitadPeriodo);

    digitalWrite(BUZZER, LOW);
    delayMicroseconds(mitadPeriodo);
  }
}


// =====================================================
// SONIDO DE EXITO
// =====================================================

void sonidoExito() {

  Serial.println("Buzzer: sonido de exito.");

  beep(1800, 400);

  delay(150);

  beep(2400, 600);
}


// =====================================================
// SONIDO DE ERROR
// =====================================================

void sonidoError() {

  Serial.println("Buzzer: sonido de error.");

  beep(500, 700);
}


// =====================================================
// DISPENSAR PRODUCTO
// =====================================================

void dispensarProducto() {

  Serial.println();
  Serial.println("================================");
  Serial.println("      DISPENSANDO PRODUCTO");
  Serial.println("================================");

  mostrarLCD(
    "Dispensando...",
    "Espere por favor"
  );

  rgbAzul();

  // ---------------------------------------------
  // POSICION INICIAL
  // ---------------------------------------------

  Serial.println("Servo -> 0 grados");

  servo.write(SERVO_CERRADO);

  delay(1000);

  // ---------------------------------------------
  // ABRIR MECANISMO
  // ---------------------------------------------

  Serial.println("Servo -> 90 grados");

  servo.write(SERVO_ABIERTO);

  delay(3000);

  // ---------------------------------------------
  // CERRAR MECANISMO
  // ---------------------------------------------

  Serial.println("Servo -> 0 grados");

  servo.write(SERVO_CERRADO);

  delay(1500);

  Serial.println("Producto dispensado.");

  sonidoExito();

  mostrarLCD(
    "Producto listo",
    "Retire producto"
  );

  rgbVerde();

  delay(2000);
}


// =====================================================
// REGISTRAR USUARIO - D
// =====================================================

void registrarUsuario() {

  String uid;

  mostrarLCD(
    "Nuevo usuario",
    "Acerque tarjeta"
  );

  rgbAzul();

  Serial.println();
  Serial.println("========== REGISTRO ==========");

  if (!esperarTarjeta(uid)) {

    mostrarLCD(
      "Tiempo agotado",
      "Intente de nuevo"
    );

    rgbRojo();

    delay(1500);

    return;
  }

  if (WiFi.status() != WL_CONNECTED) {

    mostrarLCD(
      "Sin WiFi",
      "Revise conexion"
    );

    Serial.println("ERROR: WiFi desconectado.");

    delay(1500);

    return;
  }

  HTTPClient http;

  String url = String(servidor) + "/registrar";

  http.begin(url);

  http.addHeader(
    "Content-Type",
    "application/json"
  );

  String json =
    "{\"uid\":\"" + uid + "\"}";

  Serial.println(
    "Enviando solicitud de registro..."
  );

  Serial.print("UID enviado: ");
  Serial.println(uid);

  Serial.print("URL: ");
  Serial.println(url);

  Serial.print("JSON enviado: ");
  Serial.println(json);

  int codigoHTTP = http.POST(json);

  String respuesta = http.getString();

  Serial.print("Codigo HTTP: ");
  Serial.println(codigoHTTP);

  Serial.print("Respuesta servidor: ");
  Serial.println(respuesta);

  if (codigoHTTP == 200) {

    mostrarLCD(
      "Usuario creado",
      "UID registrado"
    );

    rgbVerde();

    Serial.println(
      "RESULTADO: Usuario registrado correctamente."
    );
  }

  else if (codigoHTTP == 409) {

    mostrarLCD(
      "Ya registrado",
      "Tarjeta existe"
    );

    rgbRojo();

    Serial.println(
      "RESULTADO: Usuario ya registrado."
    );
  }

  else {

    mostrarLCD(
      "Error de servidor",
      "Intente de nuevo"
    );

    rgbRojo();

    Serial.println(
      "ERROR en registro."
    );
  }

  http.end();

  delay(2000);
}


// =====================================================
// CONSULTAR USUARIO - C
// =====================================================

void consultarUsuario() {

  String uid;

  mostrarLCD(
    "Consultar usuario",
    "Acerque tarjeta"
  );

  rgbAzul();

  Serial.println();
  Serial.println("========== CONSULTA ==========");

  if (!esperarTarjeta(uid)) {

    mostrarLCD(
      "Tiempo agotado",
      "Intente de nuevo"
    );

    delay(1500);

    return;
  }

  if (WiFi.status() != WL_CONNECTED) {

    mostrarLCD(
      "Sin WiFi",
      "Revise conexion"
    );

    Serial.println(
      "ERROR: WiFi desconectado."
    );

    delay(1500);

    return;
  }

  HTTPClient http;

  String url =
    String(servidor) +
    "/usuario/" +
    uid;

  http.begin(url);

  Serial.println(
    "Consultando usuario en servidor..."
  );

  Serial.print("UID consultado: ");
  Serial.println(uid);

  Serial.print("URL: ");
  Serial.println(url);

  int codigoHTTP = http.GET();

  String respuesta = http.getString();

  Serial.print("Codigo HTTP: ");
  Serial.println(codigoHTTP);

  Serial.print("Respuesta servidor: ");
  Serial.println(respuesta);

  if (codigoHTTP == 200) {

    int posNombre =
      respuesta.indexOf("\"nombre\"");

    String nombre = "Usuario";

    if (posNombre >= 0) {

      int inicio =
        respuesta.indexOf(":", posNombre);

      inicio++;

      while (
        respuesta[inicio] == ' ' ||
        respuesta[inicio] == '"'
      ) {
        inicio++;
      }

      int fin =
        respuesta.indexOf("\"", inicio);

      if (fin > inicio) {

        nombre =
          respuesta.substring(inicio, fin);
      }
    }

    String saldo =
      obtenerSaldoFormateado(respuesta, "saldo");

    Serial.println();
    Serial.println("RESULTADO CONSULTA");

    Serial.print("UID: ");
    Serial.println(uid);

    Serial.print("Nombre: ");
    Serial.println(nombre);

    Serial.print("Saldo: $");
    Serial.println(saldo);

    // Evita que un nombre largo invada la segunda linea
    String nombreLCD = nombre;

    if (nombreLCD.length() > 16) {
      nombreLCD = nombreLCD.substring(0, 16);
    }

    mostrarLCD(
      nombreLCD,
      "Saldo: " + saldo
    );

    rgbVerde();
  }

  else if (codigoHTTP == 404 || codigoHTTP == 400) {

    mostrarLCD(
      "Tarjeta no",
      "registrada"
    );

    rgbRojo();

    Serial.println(
      "RESULTADO: Usuario no registrado."
    );
  }

  else {

    mostrarLCD(
      "Error de servidor",
      "Intente de nuevo"
    );

    rgbRojo();

    Serial.println(
      "ERROR en consulta."
    );
  }

  http.end();

  delay(2500);
}


// =====================================================
// RECARGAR SALDO - B
// =====================================================

void recargarSaldo() {

  String montoTexto = "";

  mostrarLCD(
    "Recarga",
    "Ingrese monto:"
  );

  Serial.println();
  Serial.println("========== RECARGA ==========");

  Serial.println(
    "Ingrese monto con el teclado."
  );

  Serial.println("* = cancelar");
  Serial.println("# = confirmar");

  while (true) {

    char tecla = teclado.getKey();

    if (!tecla) {
      continue;
    }

    Serial.print("Tecla monto: ");
    Serial.println(tecla);

    if (tecla >= '0' && tecla <= '9') {

      montoTexto += tecla;

      mostrarMontoRecarga(montoTexto);
    }

    else if (tecla == '*') {

      Serial.println(
        "Recarga cancelada."
      );

      mostrarLCD(
        "Recarga",
        "Cancelada"
      );

      delay(1200);

      return;
    }

    else if (tecla == '#') {

      if (montoTexto.length() == 0) {

        mostrarLCD(
          "Ingrese monto",
          "Primero"
        );

        delay(1200);

        continue;
      }

      break;
    }
  }

  float monto =
    montoTexto.toFloat();

  Serial.print(
    "Monto confirmado: $"
  );

  Serial.println(
    monto,
    2
  );

  // Presentacion limpia sin simbolo $
  mostrarLCD(
    "Recarga: " + String(monto, 2),
    "Acerque tarjeta"
  );

  rgbAzul();

  String uid;

  if (!esperarTarjeta(uid)) {

    mostrarLCD(
      "Tiempo agotado",
      "Intente de nuevo"
    );

    delay(1500);

    return;
  }

  if (WiFi.status() != WL_CONNECTED) {

    mostrarLCD(
      "Sin WiFi",
      "Revise conexion"
    );

    Serial.println(
      "ERROR: WiFi desconectado."
    );

    delay(1500);

    return;
  }

  HTTPClient http;

  String url =
    String(servidor) +
    "/recargar";

  http.begin(url);

  http.addHeader(
    "Content-Type",
    "application/json"
  );

  String json =
    "{\"uid\":\"" + uid +
    "\",\"monto\":" +
    String(monto, 2) +
    "}";

  Serial.println(
    "Enviando solicitud de recarga..."
  );

  Serial.print("UID: ");
  Serial.println(uid);

  Serial.print("Monto: $");
  Serial.println(monto, 2);

  Serial.print("URL: ");
  Serial.println(url);

  Serial.print("JSON enviado: ");
  Serial.println(json);

  int codigoHTTP =
    http.POST(json);

  String respuesta =
    http.getString();

  Serial.print("Codigo HTTP: ");
  Serial.println(codigoHTTP);

  Serial.print("Respuesta servidor: ");
  Serial.println(respuesta);

  if (codigoHTTP == 200) {

    String saldo =
      obtenerSaldoFormateado(respuesta, "nuevo_saldo");

    // Compatibilidad con respuestas que usen "saldo".
    if (respuesta.indexOf("\"nuevo_saldo\"") < 0) {
      saldo = obtenerSaldoFormateado(respuesta, "saldo");
    }

    Serial.println(
      "RESULTADO: Recarga exitosa."
    );

    Serial.print("Nuevo saldo: $");
    Serial.println(saldo);

    mostrarLCD(
      "Recarga exitosa",
      "Saldo: " + saldo
    );

    rgbVerde();
  }

  else if (codigoHTTP == 404 || codigoHTTP == 400) {

    mostrarLCD(
      "Tarjeta no",
      "registrada"
    );

    rgbRojo();

    Serial.println(
      "RESULTADO: Usuario no registrado."
    );
  }

  else {

    mostrarLCD(
      "Error de servidor",
      "Intente de nuevo"
    );

    rgbRojo();

    Serial.println(
      "ERROR en recarga."
    );
  }

  http.end();

  delay(2500);
}


// =====================================================
// COMPRAR PRODUCTO - A
// =====================================================

void comprarProducto() {

  String producto = "";

  Serial.println();
  Serial.println("========== COMPRA ==========");

  mostrarLCD(
    "1 Cola $2.50",
    "2 Pepsi $1.00"
  );

  Serial.println("Seleccione producto:");
  Serial.println("1 = Cola ($2.50)");
  Serial.println("2 = Pepsi ($1.00)");
  Serial.println("* = cancelar");

  while (true) {

    char tecla = teclado.getKey();

    if (!tecla) {
      continue;
    }

    Serial.print(
      "Tecla producto: "
    );

    Serial.println(tecla);

    if (tecla == '1') {

      producto = "1";

      Serial.println(
        "Producto seleccionado: Cola"
      );

      Serial.println(
        "Precio: $2.50"
      );

      break;
    }

    else if (tecla == '2') {

      producto = "2";

      Serial.println(
        "Producto seleccionado: Pepsi"
      );

      Serial.println(
        "Precio: $1.00"
      );

      break;
    }

    else if (tecla == '*') {

      Serial.println(
        "Compra cancelada."
      );

      mostrarLCD(
        "Compra",
        "Cancelada"
      );

      delay(1200);

      return;
    }
  }

  if (producto == "1") {

    mostrarLCD(
      "Cola $2.50",
      "Acerque tarjeta"
    );

    rgbAzul();
  }

  else {

    mostrarLCD(
      "Pepsi $1.00",
      "Acerque tarjeta"
    );

    rgbAzul();
  }

  String uid;

  if (!esperarTarjeta(uid)) {

    mostrarLCD(
      "Tiempo agotado",
      "Intente de nuevo"
    );

    delay(1500);

    return;
  }

  if (WiFi.status() != WL_CONNECTED) {

    mostrarLCD(
      "Sin WiFi",
      "Revise conexion"
    );

    Serial.println(
      "ERROR: WiFi desconectado."
    );

    delay(1500);

    return;
  }

  HTTPClient http;

  String url =
    String(servidor) +
    "/comprar";

  http.begin(url);

  http.addHeader(
    "Content-Type",
    "application/json"
  );

  String json =
    "{\"uid\":\"" + uid +
    "\",\"producto\":\"" +
    producto +
    "\"}";

  Serial.println(
    "Enviando solicitud de compra..."
  );

  Serial.print("UID: ");
  Serial.println(uid);

  Serial.print("Producto: ");
  Serial.println(producto);

  Serial.print("URL: ");
  Serial.println(url);

  Serial.print("JSON enviado: ");
  Serial.println(json);

  int codigoHTTP =
    http.POST(json);

  String respuesta =
    http.getString();

  Serial.print("Codigo HTTP: ");
  Serial.println(codigoHTTP);

  Serial.print("Respuesta servidor: ");
  Serial.println(respuesta);

  // ===================================================
  // COMPRA EXITOSA
  // ===================================================

  if (codigoHTTP == 200) {

    String saldo =
      obtenerSaldoFormateado(respuesta, "saldo_restante");

    // Compatibilidad con respuestas que usen "saldo".
    if (respuesta.indexOf("\"saldo_restante\"") < 0) {
      saldo = obtenerSaldoFormateado(respuesta, "saldo");
    }

    Serial.println();
    Serial.println(
      "================================"
    );

    Serial.println(
      "       COMPRA EXITOSA"
    );

    Serial.println(
      "================================"
    );

    Serial.print("UID: ");
    Serial.println(uid);

    if (producto == "1") {

      Serial.println(
        "Producto: Cola"
      );

      Serial.println(
        "Precio: $2.50"
      );
    }

    else {

      Serial.println(
        "Producto: Pepsi"
      );

      Serial.println(
        "Precio: $1.00"
      );
    }

    Serial.print(
      "Saldo restante: $"
    );

    Serial.println(saldo);

    // ---------------------------------------------
    // EL SERVIDOR CONFIRMO LA COMPRA
    // AHORA SI SE MUEVE EL SERVO
    // ---------------------------------------------

    http.end();

    dispensarProducto();

    delay(500);

    mostrarLCD(
      "Compra exitosa",
      "Saldo: " + saldo
    );

    delay(2500);

    return;
  }

  // ===================================================
  // USUARIO NO REGISTRADO
  // ===================================================

  else if (codigoHTTP == 404 || codigoHTTP == 400) {

    Serial.println();
    Serial.println(
      "COMPRA RECHAZADA"
    );

    Serial.println(
      "Usuario no registrado."
    );

    mostrarLCD(
      "Tarjeta no",
      "registrada"
    );

    rgbRojo();

    sonidoError();
  }

  // ===================================================
  // SALDO INSUFICIENTE / ERROR
  // ===================================================

  else {

    Serial.println();
    Serial.println(
      "COMPRA RECHAZADA."
    );

    if (
      respuesta.indexOf(
        "Saldo insuficiente"
      ) >= 0
    ) {

      Serial.println(
        "Motivo: Saldo insuficiente."
      );

      mostrarLCD(
        "Saldo insuf.",
        "Recargue saldo"
      );

      rgbRojo();
    }

    else {

      Serial.print(
        "Motivo / HTTP: "
      );

      Serial.println(
        codigoHTTP
      );

      mostrarLCD(
        "Compra rechazada",
        "Intente de nuevo"
      );

      rgbRojo();
    }

    // NO mover servo si falla
    sonidoError();
  }

  http.end();

  delay(2500);
}


// =====================================================
// SETUP
// =====================================================

void setup() {

  Serial.begin(115200);

  delay(1000);

  Serial.println();
  Serial.println(
    "================================"
  );

  Serial.println(
    " SISTEMA NFC - VENDING MACHINE"
  );

  Serial.println(
    "================================"
  );

  // ===================================================
  // LED RGB
  // ===================================================

  pinMode(LED_R, OUTPUT);
  pinMode(LED_G, OUTPUT);
  pinMode(LED_B, OUTPUT);

  apagarRGB();

  // ===================================================
  // BUZZER
  // ===================================================

  pinMode(
    BUZZER,
    OUTPUT
  );

  digitalWrite(
    BUZZER,
    LOW
  );

  // ===================================================
  // SERVO
  // ===================================================

  servo.setPeriodHertz(50);

  servo.attach(
    SERVO_PIN,
    500,
    2400
  );

  Serial.println(
    "Servo conectado en GPIO 27."
  );

  Serial.println(
    "Posicion inicial: 0 grados."
  );

  servo.write(
    SERVO_CERRADO
  );

  delay(1000);

  // ===================================================
  // LCD
  // ===================================================

  Wire.begin(
    25,
    26
  );

  lcd.init();

  lcd.backlight();

  mostrarLCD(
    "Iniciando...",
    "Sistema NFC"
  );

  // ===================================================
  // SPI / RC522
  // ===================================================

  SPI.begin(
    18,
    19,
    23,
    5
  );

  rfid.PCD_Init();

  Serial.println(
    "RC522 inicializado."
  );

  // ===================================================
  // WIFI
  // ===================================================

  Serial.println();
  Serial.println(
    "Conectando a WiFi..."
  );

  WiFi.begin(
    ssid,
    password
  );

  int intentos = 0;

  while (
    WiFi.status() != WL_CONNECTED &&
    intentos < 30
  ) {

    delay(500);

    Serial.print(".");

    intentos++;
  }

  Serial.println();

  if (
    WiFi.status() == WL_CONNECTED
  ) {

    Serial.println(
      "WiFi conectado."
    );

    Serial.print(
      "IP ESP32: "
    );

    Serial.println(
      WiFi.localIP()
    );

    Serial.print(
      "Servidor: "
    );

    Serial.println(
      servidor
    );

    mostrarLCD(
      "WiFi conectado",
      "Sistema listo"
    );

    rgbAzul();

    delay(2000);
  }

  else {

    Serial.println(
      "ERROR: No se pudo conectar al WiFi."
    );

    mostrarLCD(
      "Error WiFi",
      "Revise conexion"
    );

    rgbRojo();

    delay(2000);
  }

  // ===================================================
  // SISTEMA LISTO
  // ===================================================

  mostrarMenuAB();

  Serial.println();
  Serial.println(
    "================================"
  );

  Serial.println(
    "          SISTEMA LISTO"
  );

  Serial.println(
    "================================"
  );

  Serial.println(
    "A = Comprar"
  );

  Serial.println(
    "B = Recargar saldo"
  );

  Serial.println(
    "C = Consultar usuario"
  );

  Serial.println(
    "D = Registrar usuario"
  );

  Serial.println();
}


// =====================================================
// LOOP
// =====================================================

void loop() {

  char tecla =
    teclado.getKey();

  if (tecla) {

    Serial.println();

    Serial.print(
      "Tecla presionada: "
    );

    Serial.println(tecla);

    // =================================================
    // CAMBIAR PAGINA DEL MENU
    // # -> C,D
    // * -> A,B
    // =================================================

    if (tecla == '#') {

      mostrarMenuCD();

      return;
    }

    else if (tecla == '*') {

      mostrarMenuAB();

      return;
    }

    // =================================================
    // A = COMPRAR
    // =================================================

    if (tecla == 'A' && !menuCD) {

      comprarProducto();
    }

    // =================================================
    // B = RECARGAR
    // =================================================

    else if (tecla == 'B' && !menuCD) {

      recargarSaldo();
    }

    // =================================================
    // C = CONSULTAR
    // =================================================

    else if (tecla == 'C' && menuCD) {

      consultarUsuario();
    }

    // =================================================
    // D = REGISTRAR
    // =================================================

    else if (tecla == 'D' && menuCD) {

      registrarUsuario();
    }

    else {

      Serial.println(
        "Tecla fuera del menu A-D."
      );
    }

    // =================================================
    // VOLVER AL MENU
    // =================================================

    mostrarMenuAB();

    Serial.println();

    Serial.println(
      "Sistema listo. Seleccione A-D."
    );
  }
}
