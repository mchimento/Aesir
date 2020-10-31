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

public class CounterPartyDetails {
	
  /* Z spec CounterPartyDetails fields */
  public short name;
  public short value;
  public short nextSeqNo;
  
  CounterPartyDetails(short name, short value, short nextSeqNo) {
	  this.name = name;
	  this.value = value;
	  this.nextSeqNo = nextSeqNo;
  }

}
