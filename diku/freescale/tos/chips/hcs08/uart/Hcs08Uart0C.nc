/* Copyright (c) 2007, Tor Petterson <motor@diku.dk>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 *  - Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *  - Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *  - Neither the name of the University of Copenhagen nor the names of its
 *    contributors may be used to endorse or promote products derived from this
 *    software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
 * SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
 * TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
  @author Tor Petterson <motor@diku.dk>
*/

configuration Hcs08Uart0C 
{
  
  provides interface StdControl;
  provides interface UartByte as UartByte;
  provides interface UartStream as UartStream;
}
implementation
{
  components CounterMicro32C as Uart0Counter;
  components Hcs08UartInterruptsP as interrupts;
  components McuSleepC;
  
  components new Hcs08UartP() as Uart0P;
  StdControl = Uart0P;
  UartByte = Uart0P;
  UartStream = Uart0P;
  Uart0P.Counter -> Uart0Counter;
  McuSleepC.McuPowerState <- Uart0P;
  
  components new HplHcs08UartP(SCI1BDH_Addr, 
                           SCI1C1_Addr, 
                           SCI1C2_Addr, 
                           SCI1C3_Addr, 
                           SCI1S1_Addr, 
                           SCI1S2_Addr, 
                           SCI1D_Addr) as HplUart0P;
  HplUart0P.RX -> interrupts.SCI1RX;
  HplUart0P.TX -> interrupts.SCI1TX;
  Uart0P.HplUart -> HplUart0P;
  
  components MainC;
  MainC.SoftwareInit -> Uart0P;
}