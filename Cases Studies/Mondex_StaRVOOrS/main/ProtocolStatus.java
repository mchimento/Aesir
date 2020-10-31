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

public class ProtocolStatus {
	
	// Z spec Wallet status
	 public final static byte Idle = 0; //originally Expecting Any To/From
	 public final static byte Epr = 1; //Expecting Request
	 public final static byte Epv = 2; //Expecting Value
	 public final static byte Epa = 3; //Expecting Acknowledge

	// Extra status (replaces final eaTo and eaFrom from the Z spec)
	 public final static byte Endf = 4; //Transaction From ended successfully
	 public final static byte Endt = 5; //Transaction To ended successfully
}
