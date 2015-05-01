import controlP5.*;
import processing.serial.*;
import java.awt.Dimension;

// Limit the minimum frame size to this value
Dimension minimumSize = new Dimension(550, 260);

// Set up the serial port
Serial serialPort;

// Set up the data export writer
PrintWriter data_export;

// Set up controlP5
ControlP5 controlP5;
controlP5.Button button_start;
controlP5.Button button_stop;
controlP5.Button button_chart_set;
controlP5.Button button_save_image;
controlP5.Button button_save_data;
CheckBox checkbox_charts;
DropdownList list_serial_ports;
controlP5.Textfield text_field_voltage;
controlP5.Textfield text_field_current;
controlP5.Textfield text_field_chart_max;
controlP5.Textfield text_field_chart_min;

// Status variables
boolean serial_selected = false; // Store whether the user has actually selected a serial port
boolean started = false; // Current running mode. 0 = Not Running, 1 = Running
boolean screenshot = false;
boolean end_requested = false;
int last_width = 0;
int last_height = 0;

// Set up the fonts we'll use
PFont axis_font;
PFont button_font;

// Chart range parameters, will be set by <FUNCTION NAME HERE> to dynamically resize based on the data
int chart_max = 50;
int chart_min = 0;

// Chart position and range parameters. Will be set by draw_chart_area() to allow resizing.
int chart_top = 0;
int chart_bottom = 0;
int chart_left = 0;
int chart_right = 0;

// Notice text
int[] notice_text_color = {255, 255, 255};
String notice_text = "NWKITS.COM BATTERY ANALYZER APPLICATION STARTED";

// Data
float[][] data = new float[131072][5];
int data_position = 0;
String in_data;
byte data_available = 0;
float[] end_data = new float[4];

// Input
float voltage_set_value = 10.65; // This gets set with the text_field_voltage box
float current_set_value = 0.5; // This gets set with the text_field_current box

// Timing
long last_time = 0;
long timer = 0;
int max_wait = 1500;

void setup(){
  size(700,380); // Set the initial window size
  frame.setTitle("NWKits.com Battery Analyzer Application V1.0");
  frame.setResizable(true); // Allow the window to be resized.
  frame.setMinimumSize(minimumSize); // Set the minimum size
  smooth(); // Enable antialiasing

  // Prepare our exit handler so we can do stuff before we quit
  // This works for hitting the close button in the bar, or selecting quit from the menu. Does not register the stop
  // button in the processing application.
  prepareExitHandler();

  // Create the font
  button_font = createFont("AurulentSansMono-Regular.otf", 20, true);
  axis_font = createFont("AurulentSansMono-Regular.otf", 11, true);
  
  // Create the controlP5 controller
  controlP5 = new ControlP5(this);
  controlP5.setAutoDraw(false);
  
  // Set up some of our controlP5 stuff
  // ###################### FIRST ROW ###########################
  list_serial_ports = controlP5.addDropdownList("serial_ports", 5, 21, 150, 50);
  list_serial_ports.bringToFront();
  list_serial_ports.setItemHeight(20);
  list_serial_ports.setBarHeight(15);
  list_serial_ports.captionLabel().set("Select Serial Port...");
  list_serial_ports.captionLabel().style().marginTop = 3;
  list_serial_ports.captionLabel().style().marginLeft = 3;
  list_serial_ports.setValue(-1);
  list_serial_ports.valueLabel().style().marginTop = 3;
  for(byte i = 0; i < serialPort.list().length; i++){
    list_serial_ports.addItem(serialPort.list()[i], i);
  }
  
  text_field_voltage = controlP5.addTextfield("text_field_voltage");
  text_field_voltage.setPosition(width - 230, 5);
  text_field_voltage.setSize(75, 15);
  text_field_voltage.setAutoClear(false);
  text_field_voltage.setLabel("Cutoff Voltage");
  text_field_voltage.setText(nf(voltage_set_value, 1, 2));
  
  text_field_current = controlP5.addTextfield("text_field_current");
  text_field_current.setPosition(width - 150, 5);
  text_field_current.setSize(75, 15);
  text_field_current.setAutoClear(false);
  text_field_current.setLabel("Discharge Current");
  text_field_current.setText(nf(current_set_value, 1, 2));
  
  button_start = controlP5.addButton("start", 1, width - 70, 5, 65, 15);
  button_start.captionLabel().setText("Start!");
              
  button_stop = controlP5.addButton("stop", 1, width - 70, 5, 65, 15);
  button_stop.captionLabel().setText("Stop!");
  button_stop.hide();
  
  // ###################### SECOND ROW ###########################
  checkbox_charts = controlP5.addCheckBox("checkbox_charts");
  checkbox_charts.setPosition(5, 40);
  checkbox_charts.setSize(15,15);
  checkbox_charts.setItemsPerRow(3);
  checkbox_charts.setSpacingColumn(50);
  checkbox_charts.addItem("Voltage", 1);
  checkbox_charts.addItem("Current", 2);
  checkbox_charts.addItem("Capacity", 3);

  text_field_chart_min = controlP5.addTextfield("text_field_chart_min");
  text_field_chart_min.setPosition(width - 230, 40);
  text_field_chart_min.setSize(75, 15);
  text_field_chart_min.setAutoClear(false);
  text_field_chart_min.setLabel("Chart Min");
  text_field_chart_min.setText(nf(chart_min, 1, 0));

  text_field_chart_max = controlP5.addTextfield("text_field_chart_max");
  text_field_chart_max.setPosition(width - 150, 40);
  text_field_chart_max.setSize(75, 15);
  text_field_chart_max.setAutoClear(false);
  text_field_chart_max.setLabel("Chart Max");
  text_field_chart_max.setText(nf(chart_max, 1, 0));
  
  button_chart_set = controlP5.addButton("chart_set", 1, width - 70, 40, 65, 15);
  button_chart_set.captionLabel().setText("Set");
  
  // ###################### THIRD ROW ###########################
  button_save_image = controlP5.addButton("save_image", 1, 5, 75, 65, 15);
  button_save_image.captionLabel().setText("Export Image");
  
  button_save_data = controlP5.addButton("save_data", 1, 75, 75, 65, 15);
  button_save_data.captionLabel().setText("Export CSV");
  
  // ###################### DROPDOWN FIX ########################
  // The dropdown will appear behind other elements because it is created earlier than them. Adding this allows the dropdown to be displayed over other elements.
  list_serial_ports.bringToFront();
}


// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// ~~ Drawing Functions
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

void draw(){
  // If the window size changes, redraw a bunch of stuff.
  if(last_width != width || last_height != height){
    println("NOTICE: Window size changed!");
    last_width = width;
    last_height = height;
    
    draw_slow();
  }
  
  // Redraw the chart slower
  if((millis() % 1000) < 25){
    draw_slow();
  }

  // Draw the controlP5 stuff. We're manually drawing the controlp5 stuff here so we can ensure it's on the screen
  // when we try and take a screenshot.
  // We're drawing this here faster so the control elements respond in a timely manner
  controlP5.draw();
  
  // Save a screenshot if requested
  if(screenshot == true) save_screenshot();
  
  // Close the serial port if requested
  if(end_requested == true) analyzer_stop_recieved();
}

void draw_slow(){
  // Draw the background
  background(92, 158, 160); // Set window background color to light blue
  
  // Make sure the objects are placed correctly
  text_field_voltage.setPosition(width - 230, 5);
  text_field_current.setPosition(width - 150, 5);
  button_start.setPosition(width - 70, 5);
  button_stop.setPosition(width - 70, 5);
  text_field_chart_min.setPosition(width - 230, 40);
  text_field_chart_max.setPosition(width - 150, 40);
  button_chart_set.setPosition(width - 70, 40);
  
  // Draw the notice text
  draw_notice_text();
  // Draw the chart
  draw_chart();
}

// Draw the notice text
void draw_notice_text(){
  // Draw the rectangle
  stroke(1, 108, 158);
  fill(2, 52, 77);
  rect(5, height - 20, width - 10, 15);
  
  // Draw the text
  fill(notice_text_color[0], notice_text_color[1], notice_text_color[2]);
  textFont(axis_font);
  textAlign(LEFT);
  text(notice_text, 8, height - 8);
}

// Draw the chart area, the grid, the axis numbers
void draw_chart(){
  // Set the current position and size parameters for the chart area. These are max values.
  // Widths will remain the same, but the height will be adjusted to fit divisions.
  int chart_x_pos = 50;
  int chart_x_width = width - 55;
  int chart_y_pos = 100;
  int chart_y_height = height - 130;
  
  // Calculate divisions
  int line_spacing = 25;
  int num_lines = (chart_y_height / line_spacing) + 1;
  
  // Resize the chart height to fit the divisions
  chart_top = chart_y_pos;
  chart_bottom = chart_y_pos + (line_spacing * (num_lines - 1));
  chart_left = chart_x_pos;
  chart_right = chart_x_pos + chart_x_width;
  
  // Draw the chart rectangle
  stroke(0); // Fill in the rectangle with color
  fill(255); // Choose white as the fill color
  rect(chart_left, chart_top, chart_right - chart_left, chart_bottom - chart_top);
  
  // Draw the horizontal lines on the chart
  for(int x = 0; x < num_lines; x++){
    line(chart_left - 5, chart_top + line_spacing * x, chart_right, chart_top + line_spacing * x);
  }
  
  // Draw the axis labels
  int chart_range = chart_max - chart_min;
  float division = (float)chart_range / (float)(num_lines - 1);
  fill(0);
  textFont(axis_font);
  textAlign(RIGHT);
  for(int x = 0; x < num_lines; x++){
    text(String.format("%.2f", chart_max - (division * x)), chart_left - 7, chart_top + line_spacing * x + 5);
  }
  
  // If we don't have any data points, don't draw anything.
  if(data_position < 2) return;
  
  int point_width = 0;
  int combined_points = 0;
  if(data_position < (chart_right - chart_left)){ // Fewer data points than pixels
    point_width = (chart_right - chart_left) / data_position;
  }else{ // More data points than pixels
    combined_points = data_position / (chart_right - chart_left) + 1;
    point_width = 1;
  }
  
  // Here's some parameters to select which data points to print
  int chart_start = 0;
  int chart_stop = data_position;
  
  // Set up some vars
  int point_y_voltage = 0;
  int point_y_current = 0;
  int point_y_capacity = 0;
  int prev_point_y_voltage = 0;
  int prev_point_y_current = 0;
  int prev_point_y_capacity = 0;
  int j = 0;
  
  // Loop through each data point
  for(int i = chart_start; i < chart_stop; i++){
    // Grab the current y values for what's selected
    if((int)checkbox_charts.getArrayValue()[0] == 1) point_y_voltage = chart_bottom + int((((data[i][2] - chart_min) * (chart_top - chart_bottom)) / chart_range)); // If voltage is selected to be graphed, calculate where
    if((int)checkbox_charts.getArrayValue()[1] == 1) point_y_current = chart_bottom + int((((data[i][3] - chart_min) * (chart_top - chart_bottom)) / chart_range)); // If current is selected to be graphed, calculate where
    if((int)checkbox_charts.getArrayValue()[2] == 1) point_y_capacity = chart_bottom + int((((data[i][4] - chart_min) * (chart_top - chart_bottom)) / chart_range)); // If capacity is selected to be graphed, calculate where
    
    // Check if the data point is above or below the chart area
    if(data[i][2] > chart_max) point_y_voltage = chart_top;
    if(data[i][2] < chart_min) point_y_voltage = chart_bottom;
    if(data[i][3] > chart_max) point_y_current = chart_top;
    if(data[i][3] < chart_min) point_y_current = chart_bottom;
    if(data[i][4] > chart_max) point_y_capacity = chart_top;
    if(data[i][4] < chart_min) point_y_capacity = chart_bottom; 

    // Calculate what our last point is
    if(i > 0){
      if((int)checkbox_charts.getArrayValue()[0] == 1) prev_point_y_voltage = chart_bottom + int((((data[i-1][2] - chart_min) * (chart_top - chart_bottom)) / chart_range)); // If voltage is selected to be graphed, calculate where
      if((int)checkbox_charts.getArrayValue()[1] == 1) prev_point_y_current = chart_bottom + int((((data[i-1][3] - chart_min) * (chart_top - chart_bottom)) / chart_range)); // If current is selected to be graphed, calculate where
      if((int)checkbox_charts.getArrayValue()[2] == 1) prev_point_y_capacity = chart_bottom + int((((data[i-1][4] - chart_min) * (chart_top - chart_bottom)) / chart_range)); // If capacity is selected to be graphed, calculate where
      
      // Check if the data point is above or below the chart area
      if(data[i-1][2] > chart_max) prev_point_y_voltage = chart_top;
      if(data[i-1][2] < chart_min) prev_point_y_voltage = chart_bottom;
      if(data[i-1][3] > chart_max) prev_point_y_current = chart_top;
      if(data[i-1][3] < chart_min) prev_point_y_current = chart_bottom;
      if(data[i-1][4] > chart_max) prev_point_y_capacity = chart_top;
      if(data[i-1][4] < chart_min) prev_point_y_capacity = chart_bottom;
    }else{ // If we're at the first point, we don't have a previous point to plot, just draw a straight line
      if((int)checkbox_charts.getArrayValue()[0] == 1) prev_point_y_voltage = point_y_voltage;
      if((int)checkbox_charts.getArrayValue()[1] == 1) prev_point_y_current = point_y_current;
      if((int)checkbox_charts.getArrayValue()[2] == 1) prev_point_y_capacity = point_y_capacity;
    }

    // If we have fewer data points than pixels, lets draw the chart by drawing lines between our current point and the last point
    if((chart_stop - chart_start) < (chart_right - (chart_left))){
      stroke(255,0,0);
      if((int)checkbox_charts.getArrayValue()[0] == 1) line(chart_left + i * point_width, prev_point_y_voltage, chart_left + i * point_width + point_width, point_y_voltage);
      stroke(0,128,0);
      if((int)checkbox_charts.getArrayValue()[1] == 1) line(chart_left + i * point_width, prev_point_y_current, chart_left + i * point_width + point_width, point_y_current);
      stroke(0,0,255);
      if((int)checkbox_charts.getArrayValue()[2] == 1) line(chart_left + i * point_width, prev_point_y_capacity, chart_left + i * point_width + point_width, point_y_capacity);
    }else{ // We have more data points than pixels, draw this by combining data points in a single horizontal pixel
      stroke(255,0,0);
      if((int)checkbox_charts.getArrayValue()[0] == 1) line(chart_left + i / combined_points, prev_point_y_voltage, chart_left + i / combined_points, point_y_voltage);
      stroke(0,128,0);
      if((int)checkbox_charts.getArrayValue()[1] == 1) line(chart_left + i / combined_points, prev_point_y_current, chart_left + i / combined_points, point_y_current);
      stroke(0,0,255);
      if((int)checkbox_charts.getArrayValue()[2] == 1) line(chart_left + i / combined_points, prev_point_y_capacity, chart_left + i / combined_points, point_y_capacity);      
    }
  }
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// ~~ Control Functions
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

void controlEvent(ControlEvent theEvent) {
//  events triggered by controllers are automatically forwarded to
//  the controlEvent method. by checking the name of a controller one can
//  distinguish which of the controllers has been changed.
  
//  check if the event is from a controller otherwise you'll get an error
//  when clicking other interface elements like Radiobutton that don't support
//  the controller() methods
  
  if(theEvent.isGroup()){
    // If the serial port selection is made, connect to the serial port
    if(theEvent.group().name()=="serial_ports"){
      println("NOTICE: serial port selected: " + theEvent.group().value());
      serial_selected = true;
      // Redraw the screen to get rid of the ghost of the dropdown.
      draw_slow();
    }
  }
  
  if(theEvent.isFrom(checkbox_charts)){
    print("Checkboxes: ");
    for(byte i = 0; i < checkbox_charts.getArrayValue().length; i++){
      print((int)checkbox_charts.getArrayValue()[i]);
      print(" - ");
    }
    println();
  }
  
  if(theEvent.isController()){
    print("control event from : "+theEvent.controller().name());
    println(", value : "+theEvent.controller().value());
    
    // If the start button is pressed, hide start, show the stop, and tell the analyzer to begin
    if(theEvent.controller().name()=="start"){
      println("NOTICE: start button pressed");
      analyzer_start();
    }

    // If the stop button is pressed, hide stop, show start, and tell the analyzer to stop
    if(theEvent.controller().name()=="stop"){
      println("NOTICE: stop button pressed");
      analyzer_stop();
    }
    
    // If the set button is pressed, lets look at what the chart range values are
    if(theEvent.controller().name()=="chart_set"){
      println("NOTICE: set button pressed");
      // Verify our chart_min & chart_max
      if(int(text_field_chart_min.getText()) < int(text_field_chart_max.getText())){
        if(((int(text_field_chart_min.getText()) >= 0 & int(text_field_chart_min.getText()) <= 60)) & (int(text_field_chart_max.getText()) >= 0 & int(text_field_chart_max.getText()) <= 60)){
          chart_min = int(text_field_chart_min.getText());
          chart_max = int(text_field_chart_max.getText());
          text_field_chart_min.setText(nf(chart_min, 1, 0));
          text_field_chart_max.setText(nf(chart_max, 1, 0));
        }else{
          println("WARNING: Chart extents parameters seem unreasonable. Setting defaults.");
          notice_text = "WARNING! CHART RANGE SEEMS UNREASONABLE. SETTING DEFAULTS.";
          chart_min = 0;
          chart_max = 50;
          text_field_chart_min.setText(nf(chart_min, 1, 0));
          text_field_chart_max.setText(nf(chart_max, 1, 0));
        }
      }else{
        println("WARNING: Chart max is not greater than chart min. Setting defaults.");
        notice_text = "WARNING! CHART MAX IS NOT GREATER THAN CHART MIN. SETTING DEFAULTS.";
        chart_min = 0;
        chart_max = 50;
        text_field_chart_min.setText(nf(chart_min, 1, 0));
        text_field_chart_max.setText(nf(chart_max, 1, 0));
      }
    }
    
    // If the save image button is pressed
    if(theEvent.controller().name()=="save_image"){
      // Doesn't seem to include the controlP5 elements. Either find a way to save just the chart area, or
      // temporarily display just the chart and save that.
      screenshot = true;
    }
    // If the save data button is pressed
    if(theEvent.controller().name()=="save_data"){
      save_csv();
    }
  } 
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// ~~ Export Functions
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// Save a screenshot of the window into the sketch folder
void save_screenshot(){
  saveFrame(year() + "-" + month() + "-" + day() + "_" + hour() + "-" + minute() + "-" + second() + ".png");
  screenshot = false;
}

// Save a copy of the data in a csv file in the sketch folder
void save_csv(){
  data_export = createWriter(year() + "-" + month() + "-" + day() + "_" + hour() + "-" + minute() + "-" + second() + ".csv");
  
  data_export.println("Time (Seconds),PWM Control,Voltage,Current,Capacity (Ah)");
  for(int i = 0; i < data_position; i++){
    data_export.println((int)data[i][0] + "," + (int)data[i][1] + "," + data[i][2] + "," + data[i][3] + "," + data[i][4]);
  }
  
  data_export.flush();
  data_export.close();
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// ~~ Analyzer Functions
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// analyzer_start needs to swap the start/stop button, open the serial port, send the PARAMETER and
// START commands to the analyzer, confirm the analyzer responds with the right parameters and that 
// the test has started, and update our status variables appropriately.
// analyzer_start is called by the press of the start button.
boolean analyzer_start(){
  println("ALERT: Beginning analysis!");
  notice_text = "BEGINNING ANALYSIS...";
  
  // Verify our setting values, (not over 50V, not over 50W)
  if(float(text_field_voltage.getText()) >= 0.0 && float(text_field_voltage.getText()) <= 50.0){
    voltage_set_value = float(text_field_voltage.getText());
    println("Voltage Set: " + voltage_set_value);
  }else{
    println("ERROR: Voltage set above safe limit of 50V!");
    notice_text = "FAILURE! CUTOFF VOLTAGE SET ABOVE 50V!";
    return false;
  }
  if(float(text_field_current.getText()) >= 0.0 && float(text_field_current.getText()) <= (50.0 / voltage_set_value) && float(text_field_current.getText()) < 10.0){
    current_set_value = float(text_field_current.getText());
    println("Current Set: " + current_set_value);
  }else{
    println("ERROR: Current set would exceed 50W discharge!");
    notice_text = "FAILURE! CURRENT SET EXCEEDS 50W OR 10A DISCHARGE! PLEASE DISCHARGE AT A LOWER RATE!";
    return false;
  } 
  
  // Open the serial port and configure to grab data on recieving '\n'
  if(!serial_open()){
    serial_selected = false;
    println("ERROR: Could not open serial port!");
    notice_text = "FAILURE! COULD NOT OPEN SERIAL PORT!";
    return false;
  }
  
  // Send the analyzer stop command just in case we left it running and are coming back to a running analyzer
  serial_write_data("$E\n");  // Send stop command
  delay(1000);
  
  // Clear extra stuff from the serial buffer so we start clean in case we've recieved other stuff
  serialPort.clear();
  
  // Check that the serial port chosen is actually the right one
  if(!analyzer_check()){
    serial_selected = false;
    println("ERROR: Analyzer is not responding on this port!");
    notice_text = "FAILURE! ANALYZER NOT RESPONDING ON THIS PORT!";
    serial_close();
    return false;
  }
  
  // Set our test parameters and confirm the set operation
  if(!analyzer_set_parameters(voltage_set_value, current_set_value)){
    println("ERROR: Analyzer does not confirm parameter set!");
    notice_text = "FAILURE! ANALYZER DOES NOT CONFIRM TEST PARAMETERS!";
    serial_close();
    return false;
  }
  
  // Clear our data array and reset the data_position value
  clear_data();
  
  // Begin the test and confirm
  serial_write_data("$B\n");
  
  timer = millis();
  while(millis() < timer + max_wait){ // wait at most max_wait for the response
    if(started == true) return true;
  }
  
  println("ERROR: Analyzer does not confirm test begin!" + in_data);
  notice_text = "FAILURE! ANALYZER DOES NOT CONFIRM TEST BEGIN!";
  serial_close();
  return false;
}

void analyzer_start_recieved(){
  button_start.hide();
  button_stop.show();
  
  started = true;
}

// analyzer_stop needs to swap the start/stop button, send the END command to the analyzer, confirm the test
// has ended, close the serial port, and adjust our status variables.
// analyzer_stop is called by the press of the stop button.
void analyzer_stop(){
  serial_write_data("$E\n");  // Send stop command
}

void analyzer_stop_recieved(){  
  println("ALERT: Ending analysis!");
  notice_text = "ANALYSIS ENDED. RUNNING TIME: " + (int)end_data[0] + " SECONDS, TOTAL CAPACITY: " + String.format("%.2f", end_data[3]) + " AMP HOURS";
  
  serial_close(); // Close the serial port
  
  button_stop.hide();
  button_start.show();
  
  end_requested = false;
}

// analyzer_set_parameters takes in what our desired parameters are, manipulates them for sending
// to the analyzer, sends them, waits for and confirms the returned data and returns true or false
// in regards to whether the parameters were successfully set.
// analyzer_set_parameters is called from analyzer_start
boolean analyzer_set_parameters(float v_cutoff, float i_limit){
  // Generate our command string
  String parameters = "$P" + nf(int(v_cutoff * 100), 4) + "," + nf(int(i_limit * 1000), 4) + "\n";
  String confirmation = "P," + String.format("%.2f", v_cutoff) + "," + String.format("%.2f", i_limit);
  data_available = 0;
  serial_write_data(parameters);
  timer = millis();
  while(millis() < timer + max_wait){ // Wait at most max_wait for the response
    if(data_available > 0){
      data_available--;
      if(in_data.equals(confirmation)){ // If the first few chars of the recieved data is what we want, return true;
        return true;
      }
    }
  }
  return false;
}

// analyzer_check sends a version command to the analyzer and waits for a response. If we get an appropriate
// version response, then we'll return true (we have a valid analyzer) or false (we don't)
// analyzer_check gets called from analyzer_start
boolean analyzer_check(){
  data_available = 0;
  serial_write_data("$V\n");
  timer = millis();
  while(millis() < timer + max_wait){ // Wait at most max_wait for the response
    if(data_available > 0){
      data_available--;
      if(in_data.substring(0, 3).equals("V,1")){ // If the first few chars of the recieved data is what we want, return true;
        return true;
      }
    }
  }
  return false;
}

// clear_data clears out the data[] array to that when we start a new test we begin with a clean slate
void clear_data(){
  for(int i = 0; i < data_position; i++){
    for(byte j = 0; j < 5; j++){
      data[i][j] = 0.0;
    }
  }
  data_position = 0;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// ~~ Serial Functions
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// Writes data to the serial port
void serial_write_data(String str){
  serialPort.write(str);
}

// Opens the serial port and configures serialEvent to be called when we recieve '\n'
boolean serial_open(){
  try {
    serialPort = new Serial(this, Serial.list()[int(list_serial_ports.value())], 19200);
  } catch (RuntimeException e){
    if(e.getMessage().contains("<init>")){
      return false;
    }
  }
  
  serialPort.bufferUntil('\n');
  
  return true;
}

// Closes the serial port
void serial_close(){
  serialPort.clear();
  serialPort.stop();
}

// serialEvent gets called automatically when the serial port recieves '\n'
void serialEvent(Serial p){
  try {
    // Send the data along to serial_read_string for parsing
    String temp_data = p.readString();
    
    // Clear extra stuff from the serial buffer so we start clean next time
    serialPort.clear();
    
    // Remove stuff we don't want
    temp_data = temp_data.replaceAll("\n", "");
    temp_data = temp_data.replaceAll("\r", "");
    
    // Do some sort of validity check...
    
    // Now that it's valid dump the raw string into the in_data variable in case other functions need it
    in_data = temp_data;
    
    // Take the data and explode it by comma
    String[] temp_data_array = split(temp_data, ',');
    
    println(temp_data);
    notice_text = temp_data;
    
    // Process what our data is and call the appropriate function
    // Is our data a data sample? D,Time,Set_PWM,Voltage,Current,Capacity
    if(temp_data_array[0].equals("D")){
      // Parse out the data
      data[data_position][0] = float(temp_data_array[1]); // Time
      data[data_position][1] = float(temp_data_array[2]); // PWM
      data[data_position][2] = float(temp_data_array[3]); // Voltage
      data[data_position][3] = float(temp_data_array[4]); // Current
      data[data_position][4] = float(temp_data_array[5]); // Capacity
      data_position++;
    }

    // Is our data a start notice? T,B,Set_Voltage,Set_Current
    // Is our data a stop notice? T,E,Time,Set_PWM,Voltage,Current,Capacity
    if(temp_data_array[0].equals("T")){
      if(temp_data_array[1].equals("B")){
        analyzer_start_recieved();
      }
      if(temp_data_array[1].equals("E")){
        if(started == true){
          started = false;
          end_requested = true;
          end_data[0] = float(temp_data_array[2]); // Time
          end_data[1] = float(temp_data_array[3]); // Voltage
          end_data[2] = float(temp_data_array[4]); // Current
          end_data[3] = float(temp_data_array[5]); // Capacity
        }
      }
    }

    // Is our data a settings confirmation? P,Set_Voltage,Set_Current
    // Is our data a version response? V,Hardware_Version,Software_Version,Name
    
    data_available++;
  } catch (Exception e){
    // Error code here 
  }
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// ~~ Closing Functions
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// shutdown() handles closing out any last things we need to do. It is called by both exit() and the exit handler to
// be able to manage sending the stop command to the battery analyzer and closing the serial port BEFORE quitting.
// Does NOT handle program exits prompted by the Processing application's stop button.
void shutdown(){
  println("SHUTDOWN");
  if(started == true) analyzer_stop();
}

// Handles exits requested by the exit button on the window
public void exit(){
  println("OverrideExit");
  shutdown();
  super.exit();
}

// Handles exits from menu quit. Also handles exits from exit button AFTER exit() does.
private void prepareExitHandler(){
  Runtime.getRuntime().addShutdownHook(new Thread(new Runnable() {
    public void run (){
      println("ExitHandler");
      shutdown();
    }
  }));
}

