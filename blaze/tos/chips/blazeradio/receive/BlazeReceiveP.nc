

/**
 * @author Jared Hill
 */

/**
 * This module assumes it already has full access to the Spi Bus
 */
 
 #include "Blaze.h"
 
module BlazeReceiveP {

  provides {
    interface Receive[ radio_id_t id ];
    interface ReceiveController[ radio_id_t id ];
    interface AckReceive;
        
    interface Init;
  }
  
  uses {
    interface AsyncSend as AckSend[ radio_id_t id ];
    interface GeneralIO as Csn[ radio_id_t id ];
   
    interface BlazeFifo as RXFIFO;
  
    interface BlazeStrobe as SFRX;
    interface BlazeStrobe as SFTX;
    interface BlazeStrobe as STX;
    interface BlazeStrobe as SNOP;
    interface BlazeStrobe as SRX;
    interface BlazeStrobe as SIDLE;
  
    interface BlazeRegister as RxReg;
    interface BlazeRegister as PktStatus;
  
    interface BlazePacket;
    interface BlazePacketBody;
    
    interface CheckRadio;
    interface RadioStatus;
    
    interface ActiveMessageAddress;
    interface State;
    interface Leds;
  }

}

implementation {

  /** ID of the radio being serviced */
  uint8_t m_id;
  
  /** Pointer to a message buffer, used for double buffering */
  message_t* m_msg;
  
  /** Acknowledgement frame */
  blaze_ack_t acknowledgement;
  
  /** Default message buffer */
  message_t myMsg;

  
  enum receive_states{
    S_IDLE,
    S_RX_LENGTH,
    S_RX_FCF,
    S_RX_PAYLOAD,
  };
  
  enum {
    BLAZE_RXFIFO_LENGTH = 64,
    MAC_PACKET_SIZE = MAC_HEADER_SIZE + TOSH_DATA_LENGTH + MAC_FOOTER_SIZE,
    SACK_HEADER_LENGTH = 5,
  };
  
  
  /***************** Prototypes ****************/
  task void receiveDone();
  
  void receive();
  void initReceive();
  uint8_t getStatus();
  void failReceive();
  
  /***************** Init Commands ****************/
  command error_t Init.init() {
    m_msg = &myMsg;
    acknowledgement.length = ACK_FRAME_LENGTH;
    acknowledgement.fcf = IEEE154_TYPE_ACK;
    return SUCCESS;
  }
  
  /***************** Receive Commands ****************/
  command void* Receive.getPayload[radio_id_t id](message_t* msg, uint8_t* len) {
    if (len != NULL) {
      *len = ((uint8_t*) (call BlazePacketBody.getHeader( msg )))[0];
    }
    return msg->data;
  }

  command uint8_t Receive.payloadLength[radio_id_t id](message_t* m) {
    uint8_t* buf = (uint8_t*)(call BlazePacketBody.getHeader( m ));
    return buf[0];
  }
  
  /*************** ReceiveController Commands ***********************/
  async command error_t ReceiveController.beginReceive[ radio_id_t id ](){
    
    uint8_t status;
    if(call State.requestState(S_RX_LENGTH) != SUCCESS) {
      return EBUSY;
    }
    
    call Csn.clr[ id ]();
    atomic{
      m_id = id;
      m_msg = &myMsg;
    }
    
    //crc check on the packet that was just received
    if((call PktStatus.read(&status)) >> 7) {
      // return SUCCESS because failReceive signals an event
      call State.toIdle();
      failReceive();
      return SUCCESS;
    }
    
    // Anything after receive() returns an event, so signal SUCCESS
    receive();
    
    return SUCCESS;
  }
  
  
  /***************** AckSend Events ****************/
  async event void AckSend.sendDone[ radio_id_t id ](void *msg, error_t error) {
    blaze_header_t *header = call BlazePacketBody.getHeader( m_msg );
    uint8_t rxFrameLength = header->length;
    uint8_t *buf = (uint8_t*) header;
    
    call RXFIFO.beginRead(buf + 1 + SACK_HEADER_LENGTH, 
          rxFrameLength - SACK_HEADER_LENGTH);
  }
  
  /***************** RXFIFO Events ****************/
  async event void RXFIFO.readDone( uint8_t* rx_buf, uint8_t rx_len,
                                    error_t error ) {

    uint8_t id;
    blaze_header_t *header = call BlazePacketBody.getHeader( m_msg );
    uint8_t rxFrameLength = header->length;
    uint8_t *buf = (uint8_t*) header;
    
    
    uint8_t* msg;
    atomic{ 
      id = m_id; 
      msg = (uint8_t*)m_msg; // TODO remove
    }
    
    //toggle csn to show done reading
    call Csn.set[ id ]();  
    call Csn.clr[ id ]();
    
    switch (call State.getState()) {
    case S_RX_LENGTH:
      call State.forceState(S_RX_FCF);
    
      if(rxFrameLength + 1 > BLAZE_RXFIFO_LENGTH) {
        // Flush everything if the length is bigger than our FIFO
        failReceive();
        return;
      
      } else {
        if(rxFrameLength <= MAC_PACKET_SIZE) {
          if(rxFrameLength > 0) {
            if(rxFrameLength > SACK_HEADER_LENGTH) {
              // This packet has an FCF byte plus at least one more byte to read
              call RXFIFO.beginRead(buf + 1, SACK_HEADER_LENGTH);
            
            } else {
              // This is really a bad packet, skip FCF and get it out of here.
              call State.forceState(S_RX_PAYLOAD);
              call RXFIFO.beginRead(buf + 1, rxFrameLength);
            }
                          
          } else {
            // Length == 0; start reading the next packet
            failReceive();
          }
        
        } else {
          // Length is too large; we have to flush the entire Rx FIFO
          failReceive();
        }
      }
      break;
            
    case S_RX_FCF:
      call State.forceState(S_RX_PAYLOAD);
      
        /*
         * Since the GDO2 goes high only when the end of the packet is reached,
         * we can safely turn into Tx mode to acknowledge reception of the
         * packet if an ack request was made.
         *
         * Our local address may have changed from the last packet received,
         * so set the outbound acknowledgement frame's source address each time
         *
         * Note that the destpan address is not checked before ack'ing.
         * To add in the destpan check, increase SACK_HEADER_LENGTH by 2 to
         * include reading in the destpan as part of the ack check, and
         * add the necessary logic to the horrendous if-statement below to
         * check the destpan.  Finally, add in a destpan address to the ack
         * frame if you want and set/check it appropriately.
         */
      
        if(FALSE) { //call BlazeConfig.isAutoAckEnabled()) {  // TODO
          if (((( header->fcf >> IEEE154_FCF_ACK_REQ ) & 0x01) == 1)
              && ((header->dest == call ActiveMessageAddress.amAddress())
                  || (header->dest == AM_BROADCAST_ADDR))
              && ((( header->fcf >> IEEE154_FCF_FRAME_TYPE ) & 7) == IEEE154_TYPE_DATA)) {
            // CSn flippage cuts off our FIFO; SACK and begin reading again
            
            acknowledgement.dest = header->src;
            acknowledgement.dsn = header->dsn;
            acknowledgement.src = call ActiveMessageAddress.amAddress();
  
            call AckSend.send[ m_id ](&acknowledgement);
            // Continues at AckSend.sendDone()
            return;
          }
        }
        
      call RXFIFO.beginRead(buf + 1 + SACK_HEADER_LENGTH, 
            rxFrameLength - SACK_HEADER_LENGTH);
      break;
      
      
    case S_RX_PAYLOAD:
      // Put the radio back in receive mode and deselect it
      initReceive();
      call Csn.set[ id ](); 
     
      // TODO check to see if we even want to do address recognition
      if((header->dest != TOS_NODE_ID) && (header->dest != AM_BROADCAST_ADDR)) {
        failReceive();
        return;
      }
      
      // The FCF_FRAME_TYPE bit in the FCF byte tells us 
      // if this is an ack or data
      if ((( header->fcf >> IEEE154_FCF_FRAME_TYPE ) & 7) == IEEE154_TYPE_ACK) {
        signal AckReceive.receive( &acknowledgement );
        call State.toIdle();
     
      } else {
        // IEEE_TYPE_DATA frame
        post receiveDone();
      }
      break;
      
    default:
      break;
    }
  }

  async event void RXFIFO.writeDone( uint8_t* tx_buf, uint8_t tx_len, error_t error ) {
  }  
  

  /***************** ActiveMessageAddress Events ****************/
  async event void ActiveMessageAddress.changed() {
  }
  
  /***************** Tasks and Functions ****************/
  task void receiveDone() {
    blaze_metadata_t *metadata = call BlazePacketBody.getMetadata( m_msg );
    uint8_t *buf = (uint8_t*) call BlazePacketBody.getHeader( m_msg );
    uint8_t rxFrameLength = buf[0];
    message_t *atomicMsg;
    uint8_t atomicId;
    
    atomic atomicId = m_id;
    
    metadata->crc = buf[ rxFrameLength ] >> 7;
    metadata->rssi = buf[ rxFrameLength - 1 ];
    metadata->lqi = buf[ rxFrameLength ] & 0x7f;
    
    atomicMsg = signal Receive.receive[atomicId]( m_msg, m_msg->data, rxFrameLength );
    atomic m_msg = atomicMsg;
    
    call State.toIdle();
  }
  
  
  void receive() {
    uint8_t status = call RadioStatus.getRadioStatus();
    
    if(status == BLAZE_S_TXFIFO_UNDERFLOW) {
      // SFTX puts us back into IDLE.  Take us out of IDLE and back into Rx
      call SFTX.strobe();
      initReceive();
    }
      
    if(status == BLAZE_S_RXFIFO_OVERFLOW) {
      // RXFIFO is corrupted, don't try and read it in.
      // need to service the interrupt or future ones won't fire
      call State.toIdle();
      failReceive();
      return; 
    }
      
    call RXFIFO.beginRead((uint8_t *) m_msg, 1);
  }
 
  void initReceive(){
    while (call RadioStatus.getRadioStatus() != BLAZE_S_RX){
      call SRX.strobe();
    }
  } 
  
  void failReceive(){
    uint8_t id;
    call SFRX.strobe();
    initReceive();
    atomic id = m_id;
    call Csn.set[ id ]();
    
    signal ReceiveController.receiveFailed[m_id]();
    return; 
  }
  
  /*************** Defaults ********************/
  default event message_t *Receive.receive[ radio_id_t id ](message_t* msg, void* payload, uint8_t len){
    return msg;
  }
  
  default async event void ReceiveController.receiveFailed[ radio_id_t id ]() {
  }
  
  default async command error_t AckSend.send[ radio_id_t id ](void *msg) {
    return FAIL;
  }
  
  default async event void AckReceive.receive( blaze_ack_t *ack ) {
  }
  
  default async command void Csn.set[ radio_id_t id ](){}
  default async command void Csn.clr[ radio_id_t id ](){}
  default async command void Csn.toggle[ radio_id_t id ](){}
  default async command bool Csn.get[ radio_id_t id ](){}
  default async command void Csn.makeInput[ radio_id_t id ](){}
  default async command bool Csn.isInput[ radio_id_t id ](){}
  default async command void Csn.makeOutput[ radio_id_t id ](){}
  default async command bool Csn.isOutput[ radio_id_t id ](){}
  
}
