package transactionsystem;

import transactionsystem.UserSession;

public class UserInfo {


	protected enum UserMode {
		ACTIVE, DISABLED, FROZEN;
	}

	public enum UserStatus {
		WHITELISTED, GREYLISTED, BLACKLISTED;
	}

	public enum UserType {
		GOLD, SILVER, NORMAL
	}
	
	protected Integer uid;
	protected String name;
	protected UserMode mode;
	protected UserStatus status;
	protected UserType type;
	protected ArraySessions sessions;
	protected ArrayAccounts accounts;
	protected int next_session_id;
	protected int next_account;
	protected String country;
	
	public UserInfo(Integer uid, String name, String country) {
		this.uid = uid;
		this.name = name;
		
		makeDisabled();
		whitelist();
		makeNormalUser();
		
		sessions = new ArraySessions();
		accounts = new ArrayAccounts();
		
		next_session_id = 0;
		next_account = 1;
		
		this.country = country;
	}
	
	// Basic information
	public Integer getId() 
	{
		return uid;
	}
	public String getName()
	{
		return name;
	}
	public String getCountry()
	{
		return country;
	}
	public ArrayAccounts getAccounts()
	{
		return accounts;
	}
	public ArraySessions getSession()
	{
		return sessions;
	}
	
	// User type
	public boolean isGoldUser() { return (type==UserType.GOLD); }
	public boolean isSilverUser() { return (type==UserType.SILVER); }
	public boolean isNormalUser() { return (type==UserType.NORMAL); }

	public void makeGoldUser() { 
		type = UserType.GOLD; 
	}
	public void makeSilverUser() { type = UserType.SILVER; }
	public void makeNormalUser() { type = UserType.NORMAL; }	
	
	// Status
	public boolean isWhitelisted() { return (status==UserStatus.WHITELISTED); }
	public boolean isGreylisted() { return (status==UserStatus.GREYLISTED); }
	public boolean isBlacklisted() { return (status==UserStatus.BLACKLISTED); }
	
	public void blacklist() 
	{ 
		status=UserStatus.BLACKLISTED; 
	}
	public void greylist() 
	{
		status=UserStatus.GREYLISTED; 
	}
	public void whitelist()
	{ 
		status=UserStatus.WHITELISTED; 
	}

	// Mode
	public boolean isActive() { return (mode==UserMode.ACTIVE); }
	public boolean isFrozen() { return (mode==UserMode.FROZEN); }
	public boolean isDisabled() { return (mode==UserMode.DISABLED); }

	public void makeActive() 
	{ 
		mode=UserMode.ACTIVE; 
	}
	public void makeFrozen() 
	{ 
		mode=UserMode.FROZEN; 
	}
	public void makeDisabled() 
	{ 
		mode=UserMode.DISABLED; 
	}
	public void makeUnfrozen() 
	{ 
		mode=UserMode.ACTIVE; 
	}

	// Sessions
	public UserSession /*@ pure @*/ getSession(int sid)
	{   return sessions.getSession(sid);
	}

	public int openSession() 
	{
		int sid = next_session_id;
		UserSession s = new UserSession(uid, sid);
		s.openSession();
		sessions.add(s);
                next_session_id++;
		return(sid);
	}

	public void closeSession(int sid) 
	{
		UserSession s = getSession(sid);
                if (s != null)
                    s.closeSession();
	}

	// Accounts
	public UserAccount getAccount(String account_number)
	{
		return accounts.getAccount(account_number);
	}

	public String createAccount(Integer sid) 
	{
		String account_number = uid.toString() + Integer.toString(next_account);
		next_account++;
		UserAccount account = new UserAccount(uid, account_number);
		accounts.add(account);
		return account_number;
	}

	public void deleteAccount(String account_number) 
	{
		UserAccount a = getAccount(account_number);
		a.closeAccount();
	}

	public void withdrawFrom(String acc_nr_wf, int amount_wf)
	{
                UserAccount acc = getAccount(acc_nr_wf) ;
                if (acc != null)
		    acc.withdraw(amount_wf);
	}

	public void depositTo(String acc_nr_dt, int amount_dt)
	{       UserAccount acc = getAccount(acc_nr_dt) ;
                if (acc != null)
                    acc.deposit(amount_dt);
	}
}
