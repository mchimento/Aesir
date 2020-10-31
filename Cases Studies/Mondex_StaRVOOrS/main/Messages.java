/************************************************************************
 * The Mondex Case Study - The StaRVOOrS Approach
 * 
 *
 * version: 1.0
 *
 * author: Jesus Mauricio Chimento (chimento@chalmers.se)
 * Chalmers University of Technology
 * http://key-project.org/
 *
 * Based on the The Mondex Case Study - The KeY Approach
 * version 1.2 by Dr. Isabel Tonin
 */

package main;

public class Messages {

	/* Messages exchanged during a payment transaction, 
	 * according the payment transaction protocol 
	 */
	  
	  /* Message labels */
	  /* CounterPayDetails message labels */
	  public final static byte StartFrom = 1;
	  public final static byte StartTo = 2;
	  
      /* PayDetails message labels */
	  public final static byte Req = 3;
	  public final static byte Val = 4;
	  public final static byte Ack = 5;	
	  
	  /* other labels - ignored in this case study */
	  public final static byte ReadExLog = 8;
	  public final static byte ClearExLog = 9;
	  
	  /* Messages content */
	  public short id; // id of the receiver
	  public byte label; 
	  public PayDetails paydetails;
	  public CounterPartyDetails cpd;
	  
	  Messages(){}
	  
	  void setPayDetailsMessage(short id, PayDetails p, byte label){
		  this.id = id;
		  paydetails = p;
		  this.label = label;
		  cpd = null;
	  }
	  
	  void setCounterPartyDetailsMessage(short id, CounterPartyDetails cpd, byte label){
		  this.id = id;		  
		  this.cpd = cpd;
		  this.label = label;
		  paydetails = null;
	  }
	  
	  
}
