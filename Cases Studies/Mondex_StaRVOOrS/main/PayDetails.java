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

public class PayDetails {
		
  /* Z spec TransferDetails fields */
  public short fromName = 0;
  public short toName = 0;
  public short value = 0;
  
  /* Z spec PayDetails extra fields */
  public short fromSeq = 0;
  public short toSeq = 0;

  protected PayDetails () {}

  public boolean equals(PayDetails x)
  {
    return (x.fromName == fromName &&
            x.toName   == toName   &&
            x.value    == value    &&
            x.fromSeq  == fromSeq  &&
            x.toSeq    == toSeq);
  }
}

