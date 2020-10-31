package transactionsystem;

public class UserSession {
	protected /*@ spec_public @*/ int sid;
	protected String log;
	protected /*@ spec_public @*/ Integer owner;
	static public Integer countLog = 0;
	
	public UserSession(Integer uid, int sid) {
		this.sid = sid;
		owner = uid;
		log = "";
	}

	public /*@ pure @*/ int getId() { return sid; }
	public Integer getOwner() { return owner; }
	public String getLog() { return log; }

	public /*@ pure @*/ void openSession() {}

	public void log(String l) 
	{ 
		log+=l+"\n"; 
		countLog++;
	}

	public /*@ pure @*/ void closeSession() {}
}
