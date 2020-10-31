package transactionsystem;

public class UserAccount {
	protected /*@ spec_public @*/ boolean opened;
	protected /*@ spec_public @*/ String account_number;

      /*@ public invariant
        @ balance >= 0;
        @*/
        protected /*@ spec_public @*/ int balance;
	protected /*@ spec_public @*/ Integer owner;
	
	public UserAccount(Integer uid, String anumber) {
		account_number = anumber;
		balance = 0;
		opened = false;
		owner = uid;
	}

    /*@
      @ public normal_behaviour
      @ ensures \result == account_number ;
      @ diverges true;
      @*/
	public /*@ pure @*/ String getAccountNumber() 
	{ 
		return account_number; 
	}

    /*@
      @ public normal_behaviour
      @ ensures \result == balance ;
      @ diverges true;
      @*/
	public /*@ pure @*/ int getBalance()
	{
		return balance;
	}
	public Integer getOwner()
	{
		return owner;
	}
	
	public void activateAccount()
	{
		opened = true;
	}
	public void closeAccount() 
	{
		opened = false;
	}

    /*@
      @ public normal_behaviour
      @ requires amount > 0 && balance >= amount;
      @ ensures balance == \old(balance) - amount ;
      @ assignable balance;
      @ diverges true;
      @*/
	public void withdraw(int amount)
	{
		balance -= amount;
	}

    /*@
      @ public normal_behaviour
      @ requires amount > 0 && balance > 0;
      @ ensures balance == \old(balance) + amount ;
      @ assignable balance;
      @ diverges true;
      @*/
	public void deposit(int amount)
	{
		balance += amount;
	}
	
}
