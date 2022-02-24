package transactionsystem;

public class ArrayAccounts {
    static final protected /*@ spec_public @*/ int Max_Accounts = 20;

    protected /*@ spec_public @*/ UserAccount[] set;

    protected /*@ spec_public @*/ int size;

    ArrayAccounts(){
        set = new UserAccount[Max_Accounts];
        size = 0;
    }

    public void add(UserAccount account) {
        if (Max_Accounts > size) {
            set[size] = account;
            size++;
        }
    }

    public UserAccount getAccount(String account_number) {
        int i = 0 ;

        while(i < size) {
            if (set[i].getAccountNumber() == account_number) return set[i] ;
            i++;
        }         
        return null;
    }

    public int getSize(){
           return size;
    }

    public UserAccount[] getSet(){
           return set;
    }
}
