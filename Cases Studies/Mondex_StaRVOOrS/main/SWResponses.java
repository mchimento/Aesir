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

public class SWResponses {

	/**********************************************************
	 * Responses for controlling erroneous situations during
	 * a payment transaction (not specified in the Z specification)
	 */

	// Process Completed
	  public final static short SW_IGNORED      = 0x6200;
	  public final static short SW_SUCCESS      = 0x6150;

	// Process Interrupted - checking error
	  public final static short SW_INVALID_CPD                 = 0x6700;
	  public final static short SW_INVALID_VALUE               = 0x6710;
	  public final static short SW_VALUE_OVERFLOW              = 0x6720;
	  public final static short SW_INSUFFICIENT_FUNDS          = 0x6730;
	  public final static short SW_LOG_FULL                    = 0x6740;
	  public final static short SW_CS_VIOLATION_LOG            = 0x6780;
	  public final static short SW_WRONG_TYPE_OF_MESSAGE       = 0x6785;
	  public final static short SW_WRONG_LABEL                 = 0x6787;
	  public final static short SW_WRONG_PARTY_DETAILS         = 0x6789;
	  public final static short SW_WRONG_Counter_Party_Details = 0x6790;
	  public final static short SW_WRONG_TRANSACTION           = 0x6750;
	  public final static short SW_TRANSACTION_FAILED          = 0x6760;	  
}
