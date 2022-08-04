#include <xc.inc>

; When assembly code is placed in a psect, it can be manipulated as a
; whole by the linker and placed in memory.  
;
; In this example, barfunc is the program section (psect) name, 'local' means
; that the section will not be combined with other sections even if they have
; the same name.  class=CODE means the barfunc must go in the CODE container.
; PIC18's should have a delta (addressible unit size) of 1 (default) since they
; are byte addressible.  PIC10/12/16's have a delta of 2 since they are word
; addressible.  PIC18's should have a reloc (alignment) flag of 2 for any
; psect which contains executable code.  PIC10/12/16's can use the default
; reloc value of 1.  Use one of the psects below for the device you use:

psect   barfunc,local,class=CODE,reloc=2 ; PIC10/12/16
; psect   barfunc,local,class=CODE,reloc=2 ; PIC18

global _gInStatus
global _gInBytes
global _gInPulseWidth
global _gOutBytesLeft
global _gLowThreshold
global _gInBitCounter
global _gProbeResponse
global _gOriginResponse
global _gInBytesLeft
global _gPollPacket
global _gInRumble
global _gOutByte
global _gOutBitCounter
global _gFSR0ptr
    
global _joybus ; extern of joybus function goes in the C source file
_joybus:
    
    ;BANKSEL(PIE1)
    ;BTFSS   PIE1, 7, 1	 ; Check if interrupt flag on. Skip if it is
    ;RETURN
    
    ;BTFSS   PIR1, 7, 1	 ; Check if we got a pulse width acquisition. Skip if yes
    ;RETURN
    
    ;BCF	    TRISB, 2	; Turn the data pin around so we can drive
    ;BCF	    PORTB, 2		; Set port to LOW
    ;NOP
    
    ;BANKSEL(_gInStatus)
    ;BTFSS   BANKMASK(_gInStatus), 0, 1	; See if we are synced up. Skip if we are.
    ;RETURN
    
    BANKSEL(_gInBytesLeft)
    
    MOVFF   BANKMASK(_gFSR0ptr), FSR0
    
    BTFSC   BANKMASK(_gInStatus), 5, 1	 ; Check if we send our poll response. Skip if not yet
    GOTO    POLLSEND
    
    BTFSC   BANKMASK(_gInStatus), 6, 1	 ; Check if we are on poll 3. Skip if not yet.
    GOTO    POLLCMD3
    
    BTFSC   BANKMASK(_gInStatus), 7, 1	 ; Check if we are on poll 2. Skip if not yet.
    GOTO    POLLCMD2
    
    
    TSTFSZ  BANKMASK(_gInBytesLeft), 1
    GOTO    READBIT
	
	; Here we will set up our command output as this is possibly a stop, but let's find out.
	; Check if we have an origin command first by checking bit position 0
	BTFSC	INDF0, 0, 0
	GOTO	ORIGINCMD
	
	; Check if we have a poll command
	BTFSC	INDF0, 6, 0
	GOTO	POLLCMD1
	
	; Treat anything else as probe
	; Set up probe response here
	MOVLW	BANKMASK(_gProbeResponse)
	MOVWF	FSR0, 0
	MOVLW	0x3
	MOVWF	BANKMASK(_gOutBytesLeft), 1
	GOTO	SENDRESPONSE
	
    ORIGINCMD:
    
	; Set up origin command response
	MOVLW	BANKMASK(_gOriginResponse)
	MOVWF	FSR0, 0
	MOVLW	0xA
	MOVWF	BANKMASK(_gOutBytesLeft), 1
	GOTO	SENDRESPONSE
    
    POLLCMD1:
	
	; Clear interrupt flag for pulse interrupt
	BCF	    PIR1, 7
	; Set up the rest of Poll CMD
	; We need to get two more bytes
	MOVLW	0x2
	MOVWF	BANKMASK(_gInBytesLeft), 1
	; Reset bits to 7. We ignore the first bit anyways.
	MOVLW	0x7
	MOVWF	BANKMASK(_gInBitCounter), 1
	; Increment our pointer to inbytes
	INCF	BANKMASK(_gFSR0ptr), 1, 1
	; Set a status flag that we are starting poll 2
	BSF	BANKMASK(_gInStatus), 7, 1
	RETURN
	
    POLLCMD2:
    
	; Clear interrupt flag for pulse interrupt
	BCF	    PIR1, 7
	; Decrement bit AND decrement byte if bits are at zero.
	DECFSZ	BANKMASK(_gInBitCounter), 1, 1
	; If bits are zero, this command is skipped.
	RETURN
	
	; We are no more bits.
	; Decrement our byte counter
	DECF	BANKMASK(_gInBytesLeft), 1, 1
	
	; Reset bits to 7. We ignore the first bit anyways.
	MOVLW	0x7
	MOVWF	BANKMASK(_gInBitCounter), 1
	; Set a status flag that we are starting poll 3
	BSF	BANKMASK(_gInStatus), 6, 1
	
    POLLCMD3:
    
	; Rotate byte to the left one
	RLNCF	INDF0, 1, 1
	; Clear the rightmost bit
	BCF	INDF0, 0, 1
    
	; Copy signal length into WREG
	MOVF    SMT1CPWL, 0, 0
	; Clear interrupt flag for pulse interrupt
	BCF	    PIR1, 7
    
	; If WREG(pulse in len) is greater than the
	; low threshold, skip setting the bit as 1.
	CPFSGT	    BANKMASK(_gLowThreshold), 1
	BSF	    INDF0, 0, 1 
    
	; Bit is written.
	; Decrement bit AND decrement byte if bits are at zero.
	DCFSNZ	BANKMASK(_gInBitCounter), 1, 1
	; Set flag so we know to send the poll response.
	BSF	BANKMASK(_gInStatus), 5, 1
	RETURN ; 46 cycles available from this point.
    
    READBIT:
	
	; Rotate byte to the left one
	RLNCF	INDF0, 1, 1
	; Clear the rightmost bit
	BCF	INDF0, 0, 1
    
	; Copy signal length into WREG
	MOVFF   BANKMASK(_gInPulseWidth), WREG
	; Clear interrupt flag for pulse interrupt
	;BCF	PIR1, 7
    
	; If WREG(pulse in len) is greater than the
	; low threshold, skip setting the bit as 1.
	CPFSLT	    BANKMASK(_gLowThreshold), 1
	BSF	    INDF0, 0, 0 
    
	; Bit is written.
	; Decrement bit AND decrement byte if bits are at zero.
	DCFSNZ	BANKMASK(_gInBitCounter), 1, 1
	; If bits aren't zero, this command is skipped.
	; Otherwise decrement the bytes remaining.
	DECF	BANKMASK(_gInBytesLeft), 1, 1
	RETURN ; 33 cycles available from this point.
    
    
    POLLSEND:
    
	; Set up origin poll response
	MOVLW	BANKMASK(_gPollPacket)
	MOVWF	FSR0, 0
	MOVLW	0x8
	MOVWF	BANKMASK(_gOutBytesLeft), 1

    SENDRESPONSE:
    
	; Disable pin interrupts
	BANKSEL(INTCON0)
	BCF	INTCON0, 7, 1
	NOP
	BANKSEL(_gOutByte)
	
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	BCF	TRISB, 2	; Turn the data pin around so we can drive
	
	; Start writing a byte
	newByte:
	    MOVFF   INDF0, _gOutByte	    ; Set the outgoing byte with the first byte.
	    CLRF    BANKMASK(_gOutBitCounter), 1	    ; Set bit counter to 0 (clear)
	    BSF	    BANKMASK(_gOutBitCounter), 3, 1   ; Set bit counter to 8.

	; Start writing our bit
	writeBit:
	    BCF	    PORTB, 2		; Set port to LOW
	    BTFSS   BANKMASK(_gOutByte), 7, 1	; Check the leftmost bit, skip if one.
	    GOTO    lowBitWrite		; Bit is 0, write a low bit out.

	; Write a high bit
	highBitWrite:		;
	    DCFSNZ  BANKMASK(_gOutBitCounter), 1, 1   ; Decrement the BIT counter. Skip next when NOT 0 to go to next bit
	    GOTO    endHighWrite
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    BSF	    PORTB, 2	; Set port to HIGH
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    GOTO    getNextBit

	lowBitWrite:		
	    DCFSNZ  BANKMASK(_gOutBitCounter), 1, 1   ; Decrement the BIT counter. Skip next when NOT 0 to go to next bit
	    GOTO    endLowWrite
	    NOP
	    NOP			
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    BSF	    PORTB, 2	; Set port to HIGH
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP

	; Load up our next bit
	getNextBit:			
	    RLCF    BANKMASK(_gOutByte), 1, 1	; Rotate the byte left so we can read the next bit
	    GOTO    writeBit		; We still have bits left, so go back up to writeBit.

	getNextByte:
	    INCF    FSR0, 1, 0		; Increment our pointer value
	    DECFSZ  BANKMASK(_gOutBytesLeft), 1, 1; Decrement our Byte counter, skip when no bytes left to write our stop bit.
	    GOTO    newByte			

	stopBitWrite:
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    BCF	    PORTB, 2	; Set port to LOW
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP	
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP	
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP	
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP	
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    BSF	    PORTB, 2	; Set port to HIGH

	    ; Perform some cleanup
	    ; Reset gInStatus
	    CLRF    BANKMASK(_gInStatus), 1
	    BSF	    BANKMASK(_gInStatus), 1, 1
	    MOVLW   0x8
	    MOVWF   BANKMASK(_gInBitCounter), 1
	    MOVWF   BANKMASK(_gOutBitCounter), 1
	    
	    BSF	TRISB, 2	; Turn the data pin around so we can listen
	    BANKSEL(PIR1)
	    ; Clear interrupt flag for pulse interrupt
	    BCF	    PIR1, 7, 1
	    BCF	    PIR1, 5, 1
	    BANKSEL(INTCON0)
	    ; Reenable interrupts
	    BSF	    INTCON0, 7, 1
	    RETURN

	endHighWrite:	
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    BSF	    PORTB, 2	; Set port to HIGH
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    GOTO    getNextByte

	endLowWrite:
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP
	    NOP			
	    NOP
	    NOP
	    NOP
	    NOP
	    BSF	    PORTB, 2	; Set port to HIGH	
	    NOP
	    NOP
	    GOTO    getNextByte

RETURN