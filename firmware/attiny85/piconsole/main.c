/*
 * piconsole - The Raspberry Pi retro videogame console project
 * Copyright (C) 2017  Michael Andrew Nixon
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Microcontroller code for ATTINY85
 * Configure the fuses to use the internal oscillator (the default) with CLKDIV8
 * Optionally enable BOD fuses at 2.7V
 *
 * Connect the pins as follows:
 *
 * 1: Reset for programmer connection / NC
 * 2: SCL for I2C (external 4.7K pullup to VCC)
 * 3: SDA for I2C (external 4.7K pullup to VCC)
 * 4: VSS
 * 5: MOSI for programmer connection / NC
 * 6: MISO for programmer connection / NC
 * 7: SCK for programmer connection / NC
 * 8: VCC (+3.5V for PS1 PSU or +5V otherwise)
 *
 * Connect I2C to a Microchip MCP23008 IO expander, wired as follows - input/output is from the MCP point of view:
 *
 *  1: SCL (I2C bus)
 *  2: SDA (I2C bus)
 *  3: VSS ]\
 *  4: VSS ] | - address configuration
 *  5: VSS ]/
 *  6: VCC
 *  7: NC
 *  8: NC
 *  9: VSS
 * 10: GP0: Output: RGB LED red anode (1K resistor for 5V, 680R for 3.5V)
 * 11: GP1: Output: RGB LED green anode (1K resistor for 5V, 680R for 3.5V)
 * 12: GP2: Output: RGB LED blue anode (1K resistor for 5V, 680R for 3.5V)
 * 13: GP3: Input : Power switch sense (internal pull-up used, button pulls to ground)
 * 14: GP4: Output: Fan control output (active high to an N-channel MOSFET, the gate should have a 47K pullup to VCC)
 * 15: GP5: Output: Raspberry Pi DC-DC board control output (active high to an NPN transistor base through a 1K resistor that pulls an P-channel MOSFET gate to ground, the gate should have a 47K pullup to the Pi DC-DC supply positive)
 * 16: GP6: Input : Raspberry Pi power-up signal (external 100K pulldown to ground)
 * 17: GP7: Output: Raspberry Pi power-down signal (through a 10K resistor just in-case)
 * 18: VCC
 *
 * Notes:
 * 0.1uF decoupling on MCU and MCP23008.
 * For PS1/PSX PSU, 2A fuse on the 8V line that feeds the DC-DC module and 0.5A fuse on the 3.3V line are ESSENTIAL FOR SAFETY!
 * Software I2C is used to avoid contention with the programming header pins (SPI)
 * VCC here means the logic supply (3.5V for PS1/PSX PSU (dual rail), 5V for single rail)
 */ 

// ------------------------------------
// Settings
// ------------------------------------
#define TRUE                0xFF
#define FALSE               0x00

#define F_CPU               1000000     // CPU clockspeed (ATTINY default from factory w/ internal oscillator and divide by 8 fusebit)
#define MCP_ADDRESS         0x40        // MCP23008 address
#define MCP_DIR_MASK        0b01001000  // MCP23008 GPIO direction mask
#define MCP_PU_MASK         0b00001000  // MCP23008 GPIO pullup mask
#define MCP_GPIO_POWERUP    0b00000000  // MCP23008 GPIO initial state

#define LED_BLINK_RATE      25          // LED blink rate (in 10ms units)
#define SHUTDOWN_WAIT_TIME  800         // Time to wait after shutdown before cutting power

// MCP GPIO pins
#define GPIO_LED_RED        0b00000001
#define GPIO_LED_GREEN      0b00000010
#define GPIO_LED_BLUE       0b00000100
#define GPIO_POWER_SWITCH   0b00001000
#define GPIO_FAN_POWER      0b00010000
#define GPIO_PI_POWER       0b00100000
#define GPIO_PI_POWERUP     0b01000000
#define GPIO_PI_POWERDOWN   0b10000000
#define GPIO_NOLED_MASK     0b11111000

// ------------------------------------
// MCP registers
// ------------------------------------
#define MCP_REG_IODIR       0x00
#define MCP_REG_IPOL        0x01
#define MCP_REG_GPINTEN     0x02
#define MCP_REG_DEFVAL      0x03
#define MCP_REG_INTCON      0x04
#define MCP_REG_IOCON       0x05
#define MCP_REG_GPPU        0x06
#define MCP_REG_INTF        0x07
#define MCP_REG_INTCAP      0x08
#define MCP_REG_GPIO        0x09
#define MCP_REG_OLAT        0x0A

// Software I2C configuration
#define I2C_DDR             DDRB
#define I2C_PIN             PINB
#define I2C_PORT            PORTB
#define I2C_SCL             PB3
#define I2C_SDA             PB4
#define I2C_DELAY           4.0
#define I2C_ACK_DELAY       2.0

#include <avr/io.h>
#include <avr/wdt.h>
#include <avr/interrupt.h>
#include <util/delay.h>

// ------------------------------------
// Function prototypes
// ------------------------------------

// Support
void mainloop(void);

// MCP23008
void MCP_init(void);
uint8_t MCP_readGPIO(void);
void MCP_writeGPIO(uint8_t data);

// Software I2C
uint8_t I2C_init(void);
void I2C_setSDAHigh(void);
void I2C_setSDALow(void);
void I2C_setSCLHigh(void);
void I2C_setSCLLow(void);
uint8_t I2C_getSDA(void);
uint8_t I2C_getSCL(void);
uint8_t I2C_start(uint8_t addr);
uint8_t I2C_repeated_start(uint8_t addr);
void I2C_stop(void);
uint8_t I2C_writebyte(uint8_t data);
uint8_t I2C_readbyte(uint8_t lastbyte);
uint8_t I2C_writeDeviceRegister(uint8_t addr, uint8_t reg, uint8_t data);
uint8_t I2C_readDeviceRegister(uint8_t addr, uint8_t reg, uint8_t *data);

// ------------------------------------
// Types
// ------------------------------------
enum eState {
  state_off,
  state_powerup_wait,
  state_on,
  state_powerdown_request,
  state_powerdown_wait
};
typedef enum eState eState;

// ------------------------------------
// Globals
// ------------------------------------

// Current machine state
eState _state;

// Current MCP GPIO state
uint8_t _gpio;

// ----------------------------------------------------------------------------
// Write to a device register
// Returns TRUE on success
// ----------------------------------------------------------------------------
uint8_t I2C_writeDeviceRegister(uint8_t addr, uint8_t reg, uint8_t data)
{
  if (I2C_start(addr)) {
    // Failed to find device
    I2C_stop();
    return FALSE;
  }
  if (I2C_writebyte(reg)) {
    // Device failed to ack register
    I2C_stop();
    return FALSE;
  }
  if (I2C_writebyte(data)) {
    // Device failed to ack data
    I2C_stop();
    return FALSE;
  }
  I2C_stop();
  return TRUE;
}

// ----------------------------------------------------------------------------
// Read from a device register
// Returns TRUE on success
// ----------------------------------------------------------------------------
uint8_t I2C_readDeviceRegister(uint8_t addr, uint8_t reg, uint8_t *data)
{
  if (I2C_start(addr)) {
    // Failed to find device
    I2C_stop();
    return FALSE;
  }
  if (I2C_writebyte(reg)) {
    // Device failed to ack register
    I2C_stop();
    return FALSE;
  }
  // Now we need to perform a repeated start to read the register
  if (I2C_repeated_start(addr | 0x01)) {
    // Failed to find device
    I2C_stop();
    return FALSE;
  }
  *data = I2C_readbyte(TRUE);
  I2C_stop();
  return TRUE;
}

// ----------------------------------------------------------------------------
// Set SDA high on the I2C bus
// ----------------------------------------------------------------------------
void I2C_setSDAHigh(void)
{
  I2C_DDR &= ~(1 << I2C_SDA);
}

// ----------------------------------------------------------------------------
// Set SDA low on the I2C bus
// ----------------------------------------------------------------------------
void I2C_setSDALow(void)
{
  I2C_DDR |= (1 << I2C_SDA);
}

// ----------------------------------------------------------------------------
// Set SCL high on the I2C bus
// ----------------------------------------------------------------------------
void I2C_setSCLHigh(void)
{
  I2C_DDR &= ~(1 << I2C_SCL);
}

// ----------------------------------------------------------------------------
// Set SCL low on the I2C bus
// ----------------------------------------------------------------------------
void I2C_setSCLLow(void)
{
  I2C_DDR |= (1 << I2C_SCL);
}

// ----------------------------------------------------------------------------
// Get SDA status
// Returns TRUE if high, FALSE if low
// ----------------------------------------------------------------------------
uint8_t I2C_getSDA(void)
{
  if (I2C_PIN & (1 << I2C_SDA)) {
    return TRUE;
  } else {
    return FALSE;
  }
}

// ----------------------------------------------------------------------------
// Get SCL status
// Returns TRUE if high, FALSE if low
// ----------------------------------------------------------------------------
uint8_t I2C_getSCL(void)
{
  if (I2C_PIN & (1 << I2C_SCL)) {
    return TRUE;
  } else {
    return FALSE;
  }
}

// ----------------------------------------------------------------------------
// Initialise the I2C bus
// Returns TRUE if successful
// ----------------------------------------------------------------------------
uint8_t I2C_init(void)
{
  // Turn off internal pullups
  I2C_PORT &= ~((1 << I2C_SDA) | (1 << I2C_SCL));
  
  I2C_setSDAHigh();
  I2C_setSCLHigh();
  
  // Give the bus time to settle
    _delay_us(10);

  // Are the pins high?
  if (!I2C_getSCL() || !I2C_getSDA()) {
    // Nope, something is wrong.
    return FALSE;
  }
  return TRUE;
}

// ----------------------------------------------------------------------------
// Start a transfer on the I2C bus with device <addr>
// Returns TRUE if successful.
// ----------------------------------------------------------------------------
uint8_t I2C_start(uint8_t addr)
{
  I2C_setSDALow();
  _delay_us(I2C_DELAY);
  I2C_setSCLLow();
  return I2C_writebyte(addr);
}

// ----------------------------------------------------------------------------
// Continue a transfer on the I2C bus with device <addr> (repeated start)
// Returns TRUE if successful.
// ----------------------------------------------------------------------------
uint8_t I2C_repeated_start(uint8_t addr)
{
  I2C_setSDAHigh();
  I2C_setSCLHigh();
  _delay_us(I2C_DELAY);
  return I2C_start(addr);
}

// ----------------------------------------------------------------------------
// Send a stop condition (release the bus)
// ----------------------------------------------------------------------------
void I2C_stop(void)
{
  I2C_setSDALow();
  _delay_us(I2C_DELAY);
  I2C_setSCLHigh();
  _delay_us(I2C_DELAY);
  I2C_setSDAHigh();
  _delay_us(I2C_DELAY);
}

// ----------------------------------------------------------------------------
// Write a byte to the I2C bus.
// Returns TRUE on ack, FALSE on nack
// ----------------------------------------------------------------------------
uint8_t I2C_writebyte(uint8_t data)
{
  uint8_t bitvalue;
  uint8_t busack;
  
  for (bitvalue = 0x80; bitvalue; bitvalue >>= 1) {
    if (bitvalue & data) {
      I2C_setSDAHigh();
    } else {
      I2C_setSDALow();
    }
    I2C_setSCLHigh();
    _delay_us(I2C_DELAY);
    I2C_setSCLLow();
    _delay_us(I2C_DELAY);
  }
  
  // Get ack or nack
  I2C_setSDAHigh();
  I2C_setSCLHigh();
  _delay_us(I2C_ACK_DELAY);
  busack = I2C_getSDA();
  I2C_setSCLLow();
  _delay_us(I2C_ACK_DELAY);
  I2C_setSDALow();
  
  return busack;
}

// ----------------------------------------------------------------------------
// Read a byte from the I2C bus. Set <lastbyte> to TRUE to send a NACK at the
// end in order to say we are finished, otherwise set it to FALSE.
// ----------------------------------------------------------------------------
uint8_t I2C_readbyte(uint8_t lastbyte)
{
  uint8_t data, i;
  
  data = 0;
  I2C_setSDAHigh();
  
  for (i = 0; i < 8; i++) {
    data <<= 1;
    _delay_us(I2C_DELAY);
    I2C_setSCLHigh();
    if (I2C_getSDA()) {
      data |= 1;
    }
    I2C_setSCLLow();
  }
  
  // If this is the last byte, send a NACK
  if (lastbyte) {
    I2C_setSDAHigh();
  } else {
    I2C_setSDALow();
  }
  
  // Twiddle the clock
  I2C_setSCLHigh();
  _delay_us(I2C_ACK_DELAY);
  I2C_setSCLLow();
  _delay_us(I2C_ACK_DELAY);
  I2C_setSDALow();
  
  return data;
}

// ----------------------------------------------------------------------------
// Initialise the MCP23008
// ----------------------------------------------------------------------------
void MCP_init(void)
{
  // Device mode: No sequential operation, no slew rate control, hardware address enabled,
  // active driven interrupt pin, normal interrupt pin polarity
  I2C_writeDeviceRegister(MCP_ADDRESS, MCP_REG_IOCON, 0b00111000);
  // Normal polarity
  I2C_writeDeviceRegister(MCP_ADDRESS, MCP_REG_IPOL, 0x00);
  // No interrupts on pin change
  I2C_writeDeviceRegister(MCP_ADDRESS, MCP_REG_GPINTEN, 0x00);
  // Apply correct pullups
  I2C_writeDeviceRegister(MCP_ADDRESS, MCP_REG_GPPU, MCP_PU_MASK);
  // Set GPIO power-up state
  I2C_writeDeviceRegister(MCP_ADDRESS, MCP_REG_GPIO, MCP_GPIO_POWERUP);
  // Set in/out pins
  I2C_writeDeviceRegister(MCP_ADDRESS, MCP_REG_IODIR, MCP_DIR_MASK);
}

// ----------------------------------------------------------------------------
// Read GPIO pins and return the state
// ----------------------------------------------------------------------------
uint8_t MCP_readGPIO(void)
{
  uint8_t data;
  I2C_readDeviceRegister(MCP_ADDRESS, MCP_REG_GPIO, &data);
  return data;
}

// ----------------------------------------------------------------------------
// Write data to the GPIO pins
// ----------------------------------------------------------------------------
void MCP_writeGPIO(uint8_t data)
{
  I2C_writeDeviceRegister(MCP_ADDRESS, MCP_REG_GPIO, data);
  _gpio = data;
}

// ----------------------------------------------------------------------------
// Main function
// ----------------------------------------------------------------------------
int main(void)
{
  // Make sure the watchdog is not running to be absolutely sure we don't reset in a loop
  // Reset watchdog if it is running
  asm("WDR");
  // Clear reset reason
  MCUSR = 0x00;
  // Prepare to disable watchdog (this actually enables it briefly)
  WDTCR |= (1 << WDCE) | (1 << WDE);
  // Now disable the watchdog
  WDTCR = 0x00;

  // Initialise all MCU pins
  // PB0 = Nothing (programmer MOSI)
  // PB1 = Nothing (programmer MISO)
  // PB2 = Nothing (programmer SCK)
  // PB3 = SCL (software I2C)
  // PB4 = SDA (software I2C)
  // PB5 = Nothing (programmer RESET)
  // Set all unused pins as outputs and pull them to ground except the reset pin
  PORTB = 0x00;
  DDRB = (1 << PB0) | (1 << PB1) | (1 << PB2);
  
  // Get the I2C bus ready and initialise the MCP23008
  I2C_init();
  MCP_init();
  
  // Default to off state
  _state = state_off;
  
  // Enter main loop now that setup is complete
  mainloop(); 
}

// ----------------------------------------------------------------------------
// Main program loop
// ----------------------------------------------------------------------------
void mainloop(void)
{
  uint8_t led_blink = FALSE, led_blink_counter = 0;
  uint16_t shutdown_timer = 0;
  uint8_t i = 0;
  
  while (1) {
    // Set LED colour depending on machine state
    switch (_state) {
      case state_off: {
        MCP_writeGPIO((_gpio & GPIO_NOLED_MASK) | GPIO_LED_RED);
        break;
      }
      case state_powerup_wait: {
        if (led_blink) {
          MCP_writeGPIO((_gpio & GPIO_NOLED_MASK) | GPIO_LED_GREEN);
        } else {
          MCP_writeGPIO(_gpio & GPIO_NOLED_MASK);
        }
        break;
      }
      case state_on: {
        MCP_writeGPIO((_gpio & GPIO_NOLED_MASK) | GPIO_LED_GREEN);
        break;
      }
      case state_powerdown_request: {
        if (led_blink) {
          MCP_writeGPIO((_gpio & GPIO_NOLED_MASK) | GPIO_LED_RED);
          } else {
          MCP_writeGPIO(_gpio & GPIO_NOLED_MASK);
        }
        break;
      }
      case state_powerdown_wait: {
        MCP_writeGPIO((_gpio & GPIO_NOLED_MASK) | GPIO_LED_RED | GPIO_LED_BLUE);
        break;
      }
    }

    // Deal with the LED blink flag   
    led_blink_counter++;
    if (led_blink_counter >= LED_BLINK_RATE) {
      led_blink_counter = 0;
      if (led_blink) {
        led_blink = FALSE;
      } else {
        led_blink = TRUE;
      }
    }
    
    // Deal with machine state transitions depending on the current state
    // This could be integrated into the previous switch statement, but this keeps it neater.
    switch (_state) {
      // Machine is off. We are waiting for the power switch to be pressed.
      case state_off: {
        // Is the power switch on?
        if (!(MCP_readGPIO() & GPIO_POWER_SWITCH)) {
          // It is. Wait for 10ms and sample it again
          _delay_ms(10);
          if (!(MCP_readGPIO() & GPIO_POWER_SWITCH)) {
            // Still latched. Begin power up sequence
            _state = state_powerup_wait;
            // Fans on
            MCP_writeGPIO(_gpio | GPIO_FAN_POWER);
            // Wait for half a second for the fans
            _delay_ms(500);
            // Pi on
            MCP_writeGPIO(_gpio | GPIO_PI_POWER);
          }
        }
        break;
      }
      // Machine is powering up. We are waiting for the Pi to signal that it has powered up.
      case state_powerup_wait: {
        // Is the Pi supplying a logic high on the powerup pin?
        if (MCP_readGPIO() & GPIO_PI_POWERUP) {
          // Yes, check it again after 10ms to be certain
          _delay_ms(10);
          if (MCP_readGPIO() & GPIO_PI_POWERUP) {
            // Pi has finished powering up.
            _state = state_on;
          }
        }
        break;
      }
      // Machine is on; check for the power button being released (and signal a power down request) and
      // also check for the Pi going into immediate shutdown
      case state_on: {
        // Did the Pi shut down?
        if (!(MCP_readGPIO() & GPIO_PI_POWERUP)) {
          // Yes, check it again after 10ms to be certain
          _delay_ms(10);
          if (!(MCP_readGPIO() & GPIO_PI_POWERUP)) {
            // Pi has shutdown.
            // First get rid of the shutdown signal, if any
            MCP_writeGPIO(_gpio & (~GPIO_PI_POWERDOWN));
            _state = state_powerdown_wait;
            shutdown_timer = 0;
          }
        } else {
          // Pi is still powered up; check if the power switch has been released.
          if ((MCP_readGPIO() & GPIO_POWER_SWITCH)) {
            // Check again after 10ms to be certain
            _delay_ms(10);
            if ((MCP_readGPIO() & GPIO_POWER_SWITCH)) {
              // Power switch released. Activate the powerdown signal.
              _state = state_powerdown_request;
              // Send out a shutdown request
              MCP_writeGPIO(_gpio | GPIO_PI_POWERDOWN);
            }
          }
        }
        break;
      }
      // Pi has been asked to power off, and should be doing so soon
      case state_powerdown_request: {
        // Did the Pi shut down?
        if (!(MCP_readGPIO() & GPIO_PI_POWERUP)) {
          // Yes, check it again after 10ms to be certain
          _delay_ms(10);
          if (!(MCP_readGPIO() & GPIO_PI_POWERUP)) {
            // Pi has shutdown.
            // First get rid of the shutdown signal, if any
            MCP_writeGPIO(_gpio & (~GPIO_PI_POWERDOWN));
            _state = state_powerdown_wait;
            shutdown_timer = 0;
          }
        }
        break;
      }
      case state_powerdown_wait: {
        // Pi has shutdown; we need to countdown before cutting power
        shutdown_timer++;
        if (shutdown_timer >= SHUTDOWN_WAIT_TIME) {
          // Time to cut power
          _state = state_off;
          // Cut power to the Pi
          MCP_writeGPIO(_gpio & (~GPIO_PI_POWER));
          // Cut power to the fans
          MCP_writeGPIO(_gpio & (~GPIO_FAN_POWER));
          // Now block in a loop until the power switch has been released for at least 1 second, incase the user pressed it again
          // Make the LED blue during this time to inform the user of this condition
          MCP_writeGPIO((_gpio & GPIO_NOLED_MASK) | GPIO_LED_BLUE);
          i = 100;
          while (i > 0) {
            i--;
            if (!(MCP_readGPIO() & GPIO_POWER_SWITCH)) {
              // Power switch is pressed, reset timer
              i = 100;
            }
            _delay_ms(10);
          }
          // Finally in powerdown state
        }
        break;
      }
    }
    
    // 10ms per loop iteration
    _delay_ms(10);
  }
}
