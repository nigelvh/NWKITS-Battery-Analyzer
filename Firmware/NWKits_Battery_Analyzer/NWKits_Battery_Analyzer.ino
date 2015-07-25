#define BAUD_RATE 19200
#define BAUD_PRESCALE (((F_CPU / (BAUD_RATE * 16UL))) - 1)

#define Hardware_Version "1.2"
#define Software_Version "1.3"
#define Description "NWKits Battery Analyzer"

#define V_Cal 3.279

#define V_Low_Pin A4
#define V_Low_Div 0.2040816327
#define V_Mid_Pin A5
#define V_Mid_Div 0.4
#define V_High_Pin A2
#define V_High_Div 0.0637580751
#define I_Sense_Pin A3
#define I_Sense_Div 0.1639344262

#define I_Sense_Res 0.1

#define Mosfet_PWM_Pin 3
#define Mosfet_PWM_Start 50

#define LED_Red 5
#define LED_Green 6

byte Console_Echo = 0;
byte Console_Input_Ready = 0;
char Console_Input[64];
byte Console_Input_Pos = 0;

float Set_Voltage = 0.0;
float Set_Current = 0.0;
unsigned int Set_PWM = Mosfet_PWM_Start;

byte test_started = 0;
unsigned long start_time = 0;
unsigned long last_time = 0;

float Voltage = 0.0;
float Current = 0.0;
float Capacity = 0.0;

ISR(USART_RX_vect){ // When the timer overflows, toggle pin on
  char temp = UDR0;
    
  // If Console_Echo is enabled, print back the char we just got
  if(Console_Echo) serial_write(temp);
    
  // If the char is a backspace, set our position back one, and set that value back to 0
  if(temp == 8 || temp == 127){
    Console_Input_Pos--;
    Console_Input[Console_Input_Pos] = 0x00;
    return;
  }
    
  // If the char is a newline/carriage return, the command is in theory done, lets parse it
  if(temp == '\n' || temp == '\r'){
    Console_Input_Ready = 1;
    return;
  }
    
  // As long as our buffer isn't full, lets dump into the buffer
  if(Console_Input_Pos < 63){
    Console_Input[Console_Input_Pos] = temp;
    Console_Input_Pos++;
  }else{ // If we get here, we've filled our buffer without getting a newline/carriage return. Just dump it.
    clear_input_buffer();
  }
}

void setup(){
  // Set up the serial connection
  UCSR0A = B00000010;
  UCSR0B = B10011000;
  UCSR0C = B00000110;
  UBRR0H = B00000000;
  UBRR0L = B01100111;
  
  // Configure the input and output pins
  pinMode(Mosfet_PWM_Pin, OUTPUT);
  analogWrite(Mosfet_PWM_Pin, 0);
  
  pinMode(LED_Red, OUTPUT);
  pinMode(LED_Green, OUTPUT);
  
  // Set the analog Reference
  analogReference(EXTERNAL);

  // Adjust PWM Frequency
  TCCR2B = TCCR2B & 0b11111000 | 0x00000001;
  
  // Do a quick startup routine
  digitalWrite(LED_Red, HIGH);
  digitalWrite(LED_Green, HIGH);
  delay(250);
  digitalWrite(LED_Red, LOW);
  delay(250);
  digitalWrite(LED_Green, LOW);
  print_version(); // Print the version on startup
  set_parameters(0,0); // Set our startup parameters to 0V cutoff and 0A current
}

void loop(){
  // Set the last_time timer
  last_time = millis();
  
  // Check for serial commands
  if(Console_Input_Ready){
    check_command();
    clear_input_buffer();
    Console_Input_Ready = 0;
  }
  
  // Set our LEDs
  if(test_started == 0) digitalWrite(LED_Green, LOW);
  
  // Check and see if we're running a test
  if(test_started == 1){
    // Flip our test running LED
    digitalWrite(LED_Green, !digitalRead(LED_Green));
    
    // Get the current info
    get_current();
    get_voltage();
    
    // Integrate the current if it's not idling
    if(Current > 0.02){
      Capacity = Capacity + (0.00027777777 * Current); // Multiply the current by the fraction of an hour represented by one second to add to the amp hour reading
    }else{
      Current = 0.0;
    }
  
    // Print out our current sample
    print_data_sample();
 
    // Check to see if we've hit the cutoff voltage on two concurrent samples
    if(Voltage < Set_Voltage && get_voltage() < Set_Voltage){ finish(); }
  
    // Adjust the current setting
    if(Current > Set_Current + 0.01 && Set_PWM > 2) Set_PWM = Set_PWM - 1; // If we're a little off, adjust a little
    if(Current < Set_Current - 0.01 && Set_PWM < 253) Set_PWM = Set_PWM + 1; // If we're a little off, adjust a little
    analogWrite(Mosfet_PWM_Pin, Set_PWM);
  }
  
  if(test_started == 2){
    // Flip our test running LED
    digitalWrite(LED_Green, !digitalRead(LED_Green));
    
    // Get the current info
    get_current();
    get_voltage();
    
    // Integrate the current if it's not idling
    if(Current > 0.02){
      Capacity = Capacity + (0.00027777777 * Current); // Multiply the current by the fraction of an hour represented by one second to add to the amp hour reading
    }else{
      Current = 0.0;
    }
  
    // Print out our current sample
    print_data_sample();
 
    // Check to see if we've hit the cutoff voltage on two concurrent samples
    if(Voltage < Set_Voltage && get_voltage() < Set_Voltage){ finish(); }
  }
  
  // Wait one second before we start again
  while(millis() < (last_time + 1000)){};
}

// Clears out Console_Input and the UART hardware buffer
void clear_input_buffer(){
  for(byte i = 0; i < 64; i++){
    Console_Input[i] = 0;
  }
  Console_Input_Pos = 0;
}

// Try to parse our command
void check_command(){
  // Check for a console echo switch
  if(Console_Input[0] == '#'){
    Console_Echo = 1;
    serial_println("\nEcho Enabled");
    return;
  }
  
  // Make sure the command starts with '$'
  if(Console_Input[0] == '$'){
    switch (Console_Input[1]){
      case 'B':
        // This is a "$B" command. Start the discharge.
        start();
        return;
      case 'M':
        // This is a "$M" command. Start a manual discharge.
        start();
        test_started = 2;
        return;
      case 'E':
        // This is a "$E" command. End the discharge.
        finish();
        return;
      case 'V':
        // This is a "$V" command. Print version info.
        print_version();
        return;
      case 'T':
        // This is a "$T" command. Print system test.
        system_test();
        return;
      case 'P':
        // We're in a parameter set command, lets read the next info, "$P1065,1000" is 10.65V cutoff and 1000mA discharge
        float v_in = 0.0;
        float i_in = 0.0;
        
        if(Console_Input_Pos != 11) break; // If we haven't got the proper number of characters for this command, break out
      
        v_in = v_in + (Console_Input[2] - '0') * 1000;
        v_in = v_in + (Console_Input[3] - '0') * 100;
        v_in = v_in + (Console_Input[4] - '0') * 10;
        v_in = v_in + (Console_Input[5] - '0') * 1;
        v_in = v_in / 100;
        if(v_in < 0 || v_in > 50) break; // If our recieved cutoff voltage isn't reasonable, break out
        
        i_in = i_in + (Console_Input[7] - '0') * 1000;
        i_in = i_in + (Console_Input[8] - '0') * 100;
        i_in = i_in + (Console_Input[9] - '0') * 10;
        i_in = i_in + (Console_Input[10] - '0') * 1;
        i_in = i_in / 1000;
        if(i_in < 0.05 || i_in > 10) break; // If our recieved discharge current isn't reasonable, break out
      
        set_parameters(v_in, i_in);
        return;
    }
  }
  
  // Use + and - to manually adjust PWM value
  if(Console_Input[0] == '+'){
    Set_PWM = Set_PWM + 1;
    analogWrite(Mosfet_PWM_Pin, Set_PWM);
    return;
  }
  if(Console_Input[0] == '-'){
    Set_PWM = Set_PWM - 1;
    analogWrite(Mosfet_PWM_Pin, Set_PWM);
    return;
  }
  
  // If we get here, command parsing failed. Blink the error LED and print an error message if Console_Echo == 1.
  if(Console_Echo){
    serial_print("Error Parsing Command: ");
    for(byte i = 0; i < Console_Input_Pos; i++){
      serial_write(Console_Input[i]);
    }
    serial_println();
  }
  
  digitalWrite(LED_Red, HIGH);
  delay(100);
  digitalWrite(LED_Red, LOW);
}

void set_parameters(float volt, float amps){
  // Set the test parameters
  Set_Voltage = volt;
  Set_Current = amps;
  
  // Print a notice
  serial_print("P,");
  serial_print(Set_Voltage, 2);
  serial_print(",");
  serial_println(Set_Current, 2);
}

void print_version(){
  // V,HardwareVersion,SoftwareVersion,Description
  serial_print("V,");
  serial_print(Hardware_Version);
  serial_print(",");
  serial_print(Software_Version);
  serial_print(",");
  serial_println(Description);
}

float get_current(){
  float temp_current[] = {0.0, 0.0, 0.0, 0.0, 0.0};
  
  // Grab a five point average for the current sense
  for(byte i = 0; i < 5; i++){ temp_current[i] = (((analogRead(I_Sense_Pin) * (V_Cal / 1024)) * I_Sense_Div) / I_Sense_Res); }
  Current = ((temp_current[0] + temp_current[1] + temp_current[2] + temp_current[3] + temp_current[4]) / 5);
  
  return Current;
}

float get_voltage(){
  float temp_volt[] = {0.0, 0.0, 0.0, 0.0, 0.0};
  float V_Low, V_Mid, V_High;
  
  // Grab a five point average for the V_Low scale
  for(byte i = 0; i < 5; i++){ temp_volt[i] = ((analogRead(V_Low_Pin) * (V_Cal / 1024)) / V_High_Div) * V_Low_Div; }
  V_Low = ((temp_volt[0] + temp_volt[1] + temp_volt[2] + temp_volt[3] + temp_volt[4]) / 5);

  // Grab a five point average for the V_Mid scale
  for(byte i = 0; i < 5; i++){ temp_volt[i] = ((analogRead(V_Mid_Pin) * (V_Cal / 1024)) / V_High_Div) * V_Mid_Div; }
  V_Mid = ((temp_volt[0] + temp_volt[1] + temp_volt[2] + temp_volt[3] + temp_volt[4]) / 5);
 
  // Grab a five point average for the V_High scale
  for(byte i = 0; i < 5; i++){ temp_volt[i] = ((analogRead(V_High_Pin) * (V_Cal / 1024)) / V_High_Div); }
  V_High = ((temp_volt[0] + temp_volt[1] + temp_volt[2] + temp_volt[3] + temp_volt[4]) / 5);
  
  // Based on what sort of voltage we're reading, select which scale we read from to get the best accuracy
  if(V_High < 10){
    Voltage = V_Low;
  }else if(V_High >= 10 && V_High < 20){
    Voltage = V_Mid;
  }else{
    Voltage = V_High;
  }
  
  return Voltage;
}

void print_data_sample(){
  serial_print("D,"); // Indicate this is a data sample
  unsigned long time = last_time - start_time;
  time = time / 1000;
  serial_print(time);
  serial_print(",");
  serial_print(Set_PWM);
  serial_print(",");
  serial_print(Voltage, 2);
  serial_print(",");
  serial_print(Current, 2);
  serial_print(",");
  serial_println(Capacity, 2);
}

void start(){
  // Start the Mosfet at a reasonable spot
  Set_PWM = Mosfet_PWM_Start;
  analogWrite(Mosfet_PWM_Pin, Set_PWM);
  
  // Begin the test
  test_started = 1;
  
  // Mark the start time
  start_time = millis();
  last_time = millis();
  
  // Print a notice
  serial_print("T,B,");
  serial_print(Set_Voltage, 2);
  serial_print(",");
  serial_println(Set_Current, 2);
}

void finish(){
  // Stop the mosfet
  Set_PWM = 2;
  analogWrite(Mosfet_PWM_Pin, Set_PWM);
  
  // End the test
  test_started = 0;
  
  // Print data
  serial_print("T,E,");
  unsigned long time = last_time - start_time;
  time = time / 1000;
  serial_print(time);
  serial_print(",");
  serial_print(Voltage, 2);
  serial_print(",");
  serial_print(Current, 2);
  serial_print(",");
  serial_println(Capacity, 2);
  
  // Reset our variables
  start_time = millis();
  last_time = millis();
  
  Voltage = 0.0;
  Current = 0.0;
  Capacity = 0.0;
}

void system_test(){
  float temp_volt[] = {0.0, 0.0, 0.0, 0.0, 0.0};
  float V_Low, V_Mid, V_High;
  
  // Grab a five point average for the V_Low scale
  for(byte i = 0; i < 5; i++){ temp_volt[i] = ((analogRead(V_Low_Pin) * (V_Cal / 1024)) / V_High_Div) * V_Low_Div; }
  V_Low = ((temp_volt[0] + temp_volt[1] + temp_volt[2] + temp_volt[3] + temp_volt[4]) / 5);

  // Grab a five point average for the V_Mid scale
  for(byte i = 0; i < 5; i++){ temp_volt[i] = ((analogRead(V_Mid_Pin) * (V_Cal / 1024)) / V_High_Div) * V_Mid_Div; }
  V_Mid = ((temp_volt[0] + temp_volt[1] + temp_volt[2] + temp_volt[3] + temp_volt[4]) / 5);
 
  // Grab a five point average for the V_High scale
  for(byte i = 0; i < 5; i++){ temp_volt[i] = ((analogRead(V_High_Pin) * (V_Cal / 1024)) / V_High_Div); }
  V_High = ((temp_volt[0] + temp_volt[1] + temp_volt[2] + temp_volt[3] + temp_volt[4]) / 5); 
  
  serial_print("T,");
  serial_print(V_Low, 2);
  serial_print(",");
  serial_print(V_Mid, 2);
  serial_print(",");
  serial_print(V_High, 2);
  serial_print(",");
  serial_println(get_current(), 2);
}

void serial_println(double n, uint8_t digits){
  serial_print(n, digits);
  serial_write(13);
  serial_write(10);
}

void serial_println(long n){
  serial_print(n);
  serial_write(13);
  serial_write(10);
}

void serial_print(double number, uint8_t digits){ 
  // Handle negative numbers
  if(number < 0.0){
     serial_write('-');
     number = -number;
  }

  // Round correctly so that print(1.999, 2) prints as "2.00"
  double rounding = 0.5;
  for (uint8_t i=0; i<digits; ++i)
    rounding /= 10.0;
  
  number += rounding;

  // Extract the integer part of the number and print it
  unsigned long int_part = (unsigned long)number;
  double remainder = number - (double)int_part;
  serial_print(int_part);

  // Print the decimal point, but only if there are digits beyond
  if(digits > 0) serial_write('.'); 

  // Extract digits from the remainder one at a time
  while(digits-- > 0){
    remainder *= 10.0;
    int toPrint = int(remainder);
    serial_print(toPrint);
    remainder -= toPrint; 
  } 
}

void serial_print(long n){
  unsigned char buf[8 * sizeof(long)];
  long i = 0;
  
  // Handle negative numbers
  if(n < 0){
    serial_write('-');
    n = -n;
  }
  
  // If it's zero, save us some work
  if(n == 0){
    serial_write('0');
    return;
  }
  
  while(n > 0){
    buf[i++] = n % 10;
    n /= 10;
  }
  
  for(; i > 0; i--){
    serial_write((char)(buf[i-1] < 10 ? '0' + buf[i - 1] : 'A' + buf[i - 1] - 10));
  }
}

void serial_println(const char *i){
  serial_print(i);
  serial_write(13);
  serial_write(10);
}

void serial_println(){
  serial_write(13);
  serial_write(10);
}

void serial_print(const char *i){
  while(*i) serial_write(*i++);
}

void serial_write(char i){
  while( !(UCSR0A & (1<<UDRE0)) ){}; // Wait until the TX circuitry is ready
  UDR0 = i;
}

