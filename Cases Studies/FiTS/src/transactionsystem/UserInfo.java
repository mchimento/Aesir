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
	
	protected /*@ spec_public @*/ Integer uid;
	protected /*@ spec_public @*/ String name;
	protected /*@ spec_public @*/ UserMode mode;
	protected /*@ spec_public @*/ UserStatus status;
	protected /*@ spec_public @*/ UserType type;
	protected /*@ spec_public @*/ ArraySessions sessions;
	protected /*@ spec_public @*/ ArrayAccounts accounts;
	protected /*@ spec_public @*/ int next_session_id;
	protected /*@ spec_public @*/ int next_account;
	protected /*@ spec_public @*/ String country;
	
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

    /*@
      @ public normal_behaviour
      @ requires \invariant_for(accounts) && \invariant_for(sessions) 
                 && (\forall int i ; i >= 0 && i < accounts.size ; accounts.set[i].balance >= 0) ;
      @ ensures (\forall int i ; i >= 0 && i < accounts.size ; accounts.set[i].balance >= 0) ;
      @ assignable \everything;
      @ diverges true;
      @*/
	public int openSession() 
	{
		int sid = next_session_id;
		UserSession s = new UserSession(uid, sid);
		s.openSession();
		sessions.add(s);
                next_session_id++;
		return(sid);
	}

    /*@
      @ public normal_behaviour
      @ requires \invariant_for(sessions) ;
      @ ensures true;
      @ assignable \everything;
      @ diverges true;
      @*/
	public void closeSession(int sid) 
	{
		UserSession s = getSession(sid);
                if (s != null)
                    s.closeSession();
	}

	// Accounts
    /*@
      @ public normal_behaviour
      @ requires \invariant_for(accounts);
      @ ensures \result == null || (\result != null && \result.getAccountNumber() == account_number) ;
      @ diverges true;
      @*/
	public /*@ pure nullable @*/ UserAccount getAccount(String account_number)
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

    /*@
      @ public normal_behaviour
      @ requires amount > 0 && \invariant_for(accounts)
                 && (\forall int i ; i >= 0 && i < accounts.size ; accounts.set[i].balance >= 0) ;
      @ ensures (\forall int i ; i >= 0 && i < accounts.size ; accounts.set[i].balance >= 0) ;
      @ assignable \everything;
      @ diverges true;
      @*/
	public void withdrawFrom(String account_number, int amount)
	{
                UserAccount acc = getAccount(account_number) ;
                if (acc != null)
		    acc.withdraw(amount);
	}

//if this precondition is used 'getAccount(account_number) != null', then
//KeY gets stuck in the loop invariant

    /*@
      @ public normal_behaviour
      @ requires amount > 0 && \invariant_for(accounts)
                 && (\forall int i ; i >= 0 && i < accounts.size ; accounts.set[i].balance >= 0) ;
      @ ensures (\forall int i ; i >= 0 && i < accounts.size ; accounts.set[i].balance >= 0) ;
      @ assignable \everything;
      @ diverges true;
      @*/
	public void depositTo(String account_number, int amount)
	{       UserAccount acc = getAccount(account_number) ;
                if (acc != null)
                    acc.deposit(amount);
	}
}
