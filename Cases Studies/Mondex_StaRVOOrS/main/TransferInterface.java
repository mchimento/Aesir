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

public class TransferInterface {
	  
  public TransferInterface(){
	  
  }
	
/******************************************************* 
 * Making a Transaction
 */
  
  boolean transferring = false;
  	 
  public short start_transfer_operation(ConPurse from, ConPurse to, short value){
	  if (transferring)
	     return SWResponses.SW_IGNORED;
	  
	  if (from.name != to.name) {
		 Mailbox mbox = new Mailbox(10);
         transferring = true;
		 
		 short ret = transfer_initialise(from, to, value, mbox);
		 if (ret != SWResponses.SW_SUCCESS)
		    return SWResponses.SW_IGNORED;
		 
		 return communication(from, to, value, mbox);
	 }
	  else {
		 return SWResponses.SW_TRANSACTION_FAILED;
	  }
  }
  
  public short transfer_initialise(ConPurse from, ConPurse to, short value, Mailbox mbox) {
	  if (!from.select(mbox))
		 return SWResponses.SW_IGNORED;
		 
	  if (!to.select(mbox))
		 return SWResponses.SW_IGNORED;		 
	  
          from.tii = this;
	  to.tii = this;

	  return SWResponses.SW_SUCCESS;
		
  }
  
  private short communication(ConPurse from, ConPurse to, short value, Mailbox mbox){	  
      CounterPartyDetails cpdForTo = new CounterPartyDetails(from.name, value, from.nextSeq);
      CounterPartyDetails cpdForFrom = new CounterPartyDetails(to.name, value, to.nextSeq);
	  
      Messages startFrom = new Messages();
	  Messages startTo = new Messages();
	  
	  startFrom.setCounterPartyDetailsMessage(from.name, cpdForFrom, Messages.StartFrom);
	  startTo.setCounterPartyDetailsMessage(to.name, cpdForTo, Messages.StartTo); 
	    
	  mbox.send(startFrom);
	  mbox.send(startTo);
	  
	  while (!mbox.isEmpty()) {
		  Messages m = mbox.receive();		  
		  if (m.id == from.name){
			  //System.out.printf("  The message is %d for %s \n", m.label, m.id);
			  from.process(m);
		  } else {
		       if (m.id == to.name) {
			      //System.out.printf("  The message is %d for %s \n", m.label, m.id);
			      to.process(m);
	           }
		    }
	  }
      return end_transfer_operation();
  }
  
  public short end_transfer_operation() {
	  transferring = false;
	  return SWResponses.SW_SUCCESS;
  } 
  
}
