/**
 * Copyright (c) 2007 Arch Rock Corporation
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the Arch Rock Corporation nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * ARCHED ROCK OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE
 */

/**
 * Counts - A TinyOS application that shows the concept of sending 
 *          a radio message.            
 *
 *           +---------+
 *           |  MainC  |
 *           +---------+
 *                | init
 *                |
 *   +-----------------------------------------------+
 *   |           ReadingsC                           |
 *   +-----------------------------------------------+
 *    |Boot |   |Leds    |   | Control            |
 *    |     |   |        |   | AMSend, Packet     |
 *    |     |   |        |   |                    |
 *    |Boot |   |Leds    |   | SplitControl       |
 *    |     |   |        |   | AMSend, Packet     |
 *  +-----+ | +-----+    | +--------------+       | 
 *  |MainC| | |LedsC|    | |ActiveMessageC|       | 
 *  +-----+ | +-----+    | +--------------+       | 
 *          |            |                        |  
 *          |Notify      |MilliTimer              | ReadVoltage
 *          |            |                        | 
 *          |            |                        |
 *          |Notify      |Timer                   | Read
 *          |            |                        | 
 *       +-----------+ +-----------+            +-----------+
 *       |UserButtonC| |TimerMilliC|            |DemoSensorC|
 *       +-----------+ +-----------+            +-----------+
 *
 * @author David Culler <dculler@archrock.com>
 * @author Jaein Jeong  <jaein@eecs.berkeley.edu>
 * @version $Revision: 1.0
 *
 */

#include "PrintCounterReading.h"

configuration ReadingsAppC {}
implementation {
  components ReadingsC, LedsC, MainC;
  components ActiveMessageC as AM;
  components new TimerMilliC();
  components UserButtonC;
  components new DemoSensorC() as VoltageSensor;

  ReadingsC.Boot -> MainC.Boot;
  ReadingsC.Control -> AM;
  ReadingsC.AMSend -> AM.AMSend[AM_PRINT_COUNTER_READING_MSG];
  ReadingsC.Leds -> LedsC;
  ReadingsC.MilliTimer -> TimerMilliC;
  ReadingsC.Packet -> AM;
  ReadingsC.Notify -> UserButtonC;
  ReadingsC.ReadVoltage -> VoltageSensor.Read;
}


