NWKits Battery Analyzer
=======

The NWKits Battery Analyzer is a device designed to provide a constant current load to test batteries or other deivces. The Analyzer is rated to handle up to 50W, and up to 50VDC.

Control of the analyzer can be achieved either via a serial terminal running at 19200 baud, via basic ASCII commands, or via a cross platform GUI application written in Processing.

This repository contains the firmware source code to be compiled in the Arduino environment, the software source code from the Processing environment and the compiled applications, as well as the build instructions and user manual.

## Supported Commands
### '#'
The '#' command will enable console echo on the device, and is recommended if your serial console does not provide console echo.

### '$V'
The '$V' command will print software version information.

```plain
$V
V,1.2,1.2,NWKits Battery Analyzer
```

### '$P'
The '$P' command is used to set test parameters. It is followed by the test cutoff voltage defined in hundredths of a volt, a comma, and the test constant current load defined in milliamps. For example, to set a cutoff voltage of 10.65V and a discharge rate of 2A, the command would be ```$P1065,2000```

The device will confirm the set parameters after your command.

```plain
$P1065,2000
P,10.65,2.00
```

### '$B'
The '$B' command is used to begin a test with the currently defined parameters.

The analyzer will confirm the test parameters, output data points once each second during the test, and at the test conclusion, print a test end summary. This example shows no battery connected, with our previously defined test parameters, so the cutoff voltage is immediately reached, and the test is ended.
```plain
$B
T,B,10.65,2.00
D,0,50,0.01,0.00,0.00
T,E,0,0.01,0.00,0.00
```
The analyzer response data fields are as follows.
Test,Begin,Voltage Cutoff,Discharge Rate
Data,Seconds Since Start,MosFET PWM Value,Voltage,Current,Accumulated Amp-Hour Capacity
Test,End,Total Seconds,End Voltage,End Current,Total Amp-Hour Capacity

### '$E'
The '$E' command is used to end a test that is currently running. After ending the test, the analyzer will print the test end summary.

### '$T'
The '$T' command is used to test analog reading methods on the analyzer, and is not needed during normal operation.

```plain
$T
T,0.01,0.02,0.00,0.01
```
The fields correspond to three voltage measurement ranges, and the measured current.

### '$M'
The '$M' command is used for manual PWM control. This mode disables constant current control as with normal tests. '$M' will begin a discharge, at the default PWM start value. Use '+' and '-' to adjust the PWM value up and down. You can use '$E' as normally to end a manual discharge.

## GUI Application
Further information on using the GUI application is available in the user manual document. In summary, the steps using the GUI application will involve selecting the analyzer serial device from the drop down, setting the cutoff voltage and discharge current, and pressing the START button. There are tick boxes to enable plotting Voltage, Current, and Capacity, and fields to enter integer values for the chart vertical extents. Additionally, there are buttons to export a image capture of the chart, and to export the data as a CSV file. These files will be placed in the same directory the application is running from.

## Drivers
The analyzer is automatically recognized as a USB serial device under OSX and Linux, however, windows requires a driver to associate the device with the built in USB serial device drivers. If you have used an Arduino device like the Duemilanove, these drivers are most likely already installed. If they are not, the drivers are available at http://www.ftdichip.com/Drivers/VCP.htm
