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

public class Mailbox {
	
	private Messages[] buffer;
	private int capacity;
	private int size;

	Mailbox(int capacity){
		buffer = new Messages[capacity];
		this.capacity = capacity;
		size = 0;
	}
	
	public synchronized void send(Messages m) {
		if (size < capacity) {			
			buffer[size] = m;
			size++;
		}
	}
	
	public synchronized Messages receive() {
		if (!isEmpty()) {		   
		   Messages m = buffer[0];
		   int i = 0;

		    while (i < size-1){
			    buffer[i] = buffer[i+1];
			    i++;
		    }
		   
		    buffer[size-1] = null;
		    size--;
            return m;		   
		} else {
             // If proper message passing is used, this should be a wait case
		     return null;
		     }
	}

	public boolean isEmpty() {
		return buffer[0] == null;		
	}
	
}
