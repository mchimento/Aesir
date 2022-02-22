/************************************************************************
 * The Mondex Case Study - The StaRVOOrS Approach
 * Purse main class
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

public class ConPurse
{

/**********************************************************
 * The Application
 **********************************************************/

/**********************************************************
 * Implementation Specific Constants declaration
 */
// maximum value that a variable can hold
  public final static short ShortMaxValue = 32767;
  
/**********************************************************
 * Fields declaration (according to the Z specification)
 */
  public short balance;
  public PayDetails[] exLog;
  public short name;
  public short nextSeq;
  public byte status;
  public byte logIdx;

  // actual transaction details
  public PayDetails transaction;

  
  /**********************************************************
   * Mailbox for message passing between purses
   */ 
  //Message passing
  public Mailbox mailbox;
  
  /**********************************************************
   * Ghost Information of the transfer 
   */ 
   public TransferInterface tii = new TransferInterface();
 
/**********************************************************
 * Methods 
 */

// Constructor: an instance of class ConPurseJC is instantiated by its
// install method.  
  public ConPurse (short id)
  {
      name = id;
      nextSeq = 0;
      balance = 0;
      status = ProtocolStatus.Idle;
      exLog = new PayDetails[25];
      for(short i=0; i<exLog.length; i++)
      {
        exLog[i] = new PayDetails();
      }
      transaction = new PayDetails();
      logIdx = 0;
      mailbox = null;
  }
 
  public void setMailbox(Mailbox mbox){
	  mailbox = mbox;
  }
   
  public short chargeMoney(short value){
	  if (value > (short) (ShortMaxValue - balance))
          return SWResponses.SW_VALUE_OVERFLOW;
	  else {
	     balance = (short) (balance + value);
	     return SWResponses.SW_SUCCESS;
	     }
  }
  

// This method is called to indicate that this purse has been
// selected.  It performs the initialization required to process the
// subsequent messages.  The purse can decline to be selected, for
// instance, if the pin is blocked.  In this case study, it does not
// perform any initialization and always accept the selection.
// The abort operation is performed in order put the
// purse in a Idle state ready to start a new transaction, logging the old
// transaction if necessary.
  public boolean select(Mailbox mbox)
  {	  
	  // A purse can be involved only in one transaction at a time
	  // It is assumed that it is only possible to initialise a connection with one purse
	   mailbox = mbox;
       abort_if_necessary();      
       return true;
  }

// This method is called to inform the purse that it should
// perform any clean-up and bookkeeping tasks before it is
// deselected.
// For the case study not clean-up operation was defined.
  public void deselect()
  {
	 return;
  }

  
  public short process(Messages m)
  {
	  //Ignores message not sent to this purse
	  if (m == null)
		 return SWResponses.SW_IGNORED;
	  
	  if (m.id != name)
		 return SWResponses.SW_IGNORED;
	  	  
	  //Invalid paydetails message
	  if (m.paydetails != null) {
		  if (m.paydetails.fromName != name && m.paydetails.toName != name)
			  return SWResponses.SW_WRONG_PARTY_DETAILS;
	  }
	  	  
	  // Invalid cpd message
	  if (m.cpd != null) {
		  if (m.cpd.name == name || !(m.cpd.name > 0) || (m.cpd.nextSeqNo < 0))
			 return SWResponses.SW_INVALID_CPD;
	  }	         
	  	  
	  short ret;
	  
	  //Calls the method indicated by the label of the message
      switch (m.label)
      {
      case Messages.StartFrom: start_from_operation(m); break;
      case Messages.StartTo: 
    	                     ret = start_to_operation(m);
    	                     if (ret == SWResponses.SW_SUCCESS) {
                                m.setPayDetailsMessage(transaction.fromName, transaction, Messages.Req);
                                mailbox.send(m);
                             }
                             break;
      case Messages.Req: 
    	                 ret = req_operation(m); 
    	                 if (ret == SWResponses.SW_SUCCESS) {
    	                    m.setPayDetailsMessage(transaction.toName, transaction, Messages.Val);
    	                    mailbox.send(m);
    	                 }
    	                 break;
      case Messages.Val: 
    	                 ret = val_operation(m); 
    	                 if (ret == SWResponses.SW_SUCCESS) {
    	                     m.setPayDetailsMessage(transaction.fromName, transaction, Messages.Ack);
    	                     mailbox.send(m);
    	                 }
    	                 break;
      case Messages.Ack: ack_operation(m); break;
      case Messages.ReadExLog: read_ex_log_operation(m); break;
      case Messages.ClearExLog: clear_ex_log_operation(m); break;
      default: return SWResponses.SW_WRONG_LABEL;
      }
      return SWResponses.SW_SUCCESS;
  }
  
/**********************************************************
 * Application Specific Methods
 */

  private short abort_if_necessary()
  {
    if (!((status == ProtocolStatus.Epv) || (status == ProtocolStatus.Epa)))
    {
      status = ProtocolStatus.Idle;
      return SWResponses.SW_SUCCESS;
    }
    else if (logIdx >= exLog.length)
    {  
       return SWResponses.SW_LOG_FULL;
    }
    else
    {   
        exLog[logIdx] = transaction;
        logIdx++;
        status = ProtocolStatus.Idle;
        return SWResponses.SW_CS_VIOLATION_LOG;
      }          
  }

 
  private short start_from_operation(Messages m_sf)
  {    
    if (status == ProtocolStatus.Idle)
    { 
      if (logIdx >= exLog.length) return SWResponses.SW_LOG_FULL;
      
      short aux = readCounterPartDetails(m_sf);
      if (aux == SWResponses.SW_SUCCESS){
         if (nextSeq < ShortMaxValue)
            nextSeq = (short) (nextSeq + 1);
         else nextSeq = 0;
         status = ProtocolStatus.Epr;    
         return SWResponses.SW_SUCCESS;
      }
      else {
    	  return SWResponses.SW_WRONG_Counter_Party_Details;
      }
    }
    else return SWResponses.SW_IGNORED;
  }

  private short start_to_operation(Messages m)
  {    
    if (status == ProtocolStatus.Idle)
    {
      if (logIdx >= exLog.length) return SWResponses.SW_LOG_FULL;
      
      short aux = readCounterPartDetails(m);
      if (aux == SWResponses.SW_SUCCESS){
         if (nextSeq < ShortMaxValue)
            nextSeq = (short) (nextSeq + 1);
         else nextSeq = 0;
         status = ProtocolStatus.Epv;       
         
         return SWResponses.SW_SUCCESS;      
      }
      else {
    	  return SWResponses.SW_WRONG_Counter_Party_Details;
      }
    }
    else return SWResponses.SW_IGNORED;
  }
  
  private short req_operation(Messages m_r)
  {
    if (status == ProtocolStatus.Epr)
    {
      short aux = checkSameTransaction(m_r);
      if (aux == SWResponses.SW_SUCCESS) {
         balance = (short)(balance - transaction.value);
         status = ProtocolStatus.Epa;         
         
         return SWResponses.SW_SUCCESS;
      } else {
    	  return SWResponses.SW_WRONG_TRANSACTION;
      }
    }
    else return SWResponses.SW_IGNORED;
  }

  private short val_operation(Messages m)
  {
    if (status == ProtocolStatus.Epv) {    	
      short aux = checkSameTransaction(m);
      
      if (aux == SWResponses.SW_SUCCESS){
         balance = (short)(balance + transaction.value);
         status = ProtocolStatus.Endt;     
         
         return SWResponses.SW_SUCCESS;
      } else {
    	  return SWResponses.SW_WRONG_TRANSACTION;
      }
    }
    else return SWResponses.SW_IGNORED;
  }


  private short ack_operation(Messages m_a)
  {
    if (status == ProtocolStatus.Epa)
    {
      short aux = checkSameTransaction(m_a);
      
      if (aux == SWResponses.SW_SUCCESS) {
         status = ProtocolStatus.Endf;
         return SWResponses.SW_SUCCESS;
      } else {
    	  return SWResponses.SW_WRONG_TRANSACTION;
      }
    }
    else return SWResponses.SW_IGNORED;
  }

  private short read_ex_log_operation(Messages m)
  {   
	  if (status == ProtocolStatus.Idle)
	     return SWResponses.SW_SUCCESS;
	  else {
		 return SWResponses.SW_IGNORED;    
	  }
  }

  private short clear_ex_log_operation(Messages m)
  {
	  if (status == ProtocolStatus.Idle)
		 return SWResponses.SW_SUCCESS;
	  else {
		 return SWResponses.SW_IGNORED;    
	 }
  }

  public short readCounterPartDetails(Messages m) {    
      if (m.cpd != null){
    	 if (m.cpd.name != name) { 
	         short cpdName = m.cpd.name;
             short cpdSeq = m.cpd.nextSeqNo;
             short value = m.cpd.value;
             return parseCounterPartDetails(cpdName, cpdSeq,value,m.label);
         } else {
        	 return SWResponses.SW_WRONG_TYPE_OF_MESSAGE; 
         }
      }
      return SWResponses.SW_WRONG_TYPE_OF_MESSAGE;
  }

  public short parseCounterPartDetails(short cpdName, short cpdSeq, short value, byte ins)
  {   
      if ((cpdName == name) || !(cpdName > 0) || (cpdSeq < 0))
         return SWResponses.SW_INVALID_CPD;
      
      if (value <= 0) return SWResponses.SW_INVALID_VALUE;
      
      if (ins == Messages.StartFrom)
        if (value > balance)
           return SWResponses.SW_INSUFFICIENT_FUNDS;
        else
        {
          transaction.fromName = name;
          transaction.toName = cpdName;
          transaction.fromSeq = nextSeq;
          transaction.toSeq = cpdSeq;
          transaction.value = value;
          return SWResponses.SW_SUCCESS;
        }
      
      if (ins == Messages.StartTo)
        if (value > (short) (ShortMaxValue - balance))
           return SWResponses.SW_VALUE_OVERFLOW;
        else
        {
          transaction.fromName = cpdName;
          transaction.toName = name;
          transaction.fromSeq = cpdSeq;
          transaction.toSeq = nextSeq;
          transaction.value = value;
          return SWResponses.SW_SUCCESS;
        }
      
       return SWResponses.SW_WRONG_TYPE_OF_MESSAGE;
}
  
  public short checkSameTransaction(Messages m)
  {
	if (m.cpd != null)  
	   return SWResponses.SW_WRONG_TYPE_OF_MESSAGE;
			   
	if (m.paydetails != null) {  
       if (!m.paydetails.equals(transaction))
          return SWResponses.SW_WRONG_TRANSACTION ;
       return SWResponses.SW_SUCCESS;
    }
	
	return SWResponses.SW_WRONG_TYPE_OF_MESSAGE;
  }
}

