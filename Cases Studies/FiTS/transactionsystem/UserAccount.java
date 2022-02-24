package transactionsystem;

public class UserAccount {
	protected boolean opened;
	protected String account_number;

        protected int balance;
	protected Integer owner;
	
	public UserAccount(Integer uid, String anumber) {
		account_number = anumber;
		balance = 0;
		opened = false;
		owner = uid;
	}

	public String getAccountNumber() 
	{ 
		return account_number; 
	}

	public int getBalance()
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

	public void withdraw(int amount)
	{
		balance -= amount;
	}

	public void deposit(int amount)
	{
		balance += amount;
	}	
}
