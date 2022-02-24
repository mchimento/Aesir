package transactionsystem;

public class ArraySessions {
    static final protected int Max_Sessions = 20; 

    protected UserSession[] set;

    protected int size;

    ArraySessions(){
        set = new UserSession[Max_Sessions];
        size = 0;
    }

    public void add(UserSession session) {
        if (Max_Sessions > size) {
            set[size] = session;
            size++;
        }
    }

    public UserSession getSession(int sid) {
        int i = 0 ;

        while(i < size) {
            if (set[i].getId() == sid) return set[i] ;
            i++;
        }         
        return null;
    }

    public int getSize(){
           return size;
    }

    public UserSession[] getSet(){
           return set;
    }
}
