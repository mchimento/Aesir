package transactionsystem;

public class ArrayAccounts {
    static final protected /*@ spec_public @*/ int Max_Accounts = 20;

  /*@ public invariant
    @ set.length == Max_Accounts && set != null;
    @*/

    /*@ public invariant \typeof(set) == \type(Object[]) ; @*/    

    protected /*@ spec_public @*/ UserAccount[] set;

  /*@ public invariant
    @ size >= 0 && size <= Max_Accounts 
      && (\forall int i ; i >= 0 && i < size ; set[i] != null) ;
    @*/
    protected /*@ spec_public @*/ int size;

    ArrayAccounts(){
        set = new UserAccount[Max_Accounts];
        size = 0;
    }

    /*@
      @ public normal_behaviour
      @ requires account != null && Max_Accounts > size ;
      @ ensures size == \old(size) + 1 && set[\old(size)] == account ;
      @ assignable size,set[size] ;
      @ diverges true;
      @*/
    public void add(UserAccount account) {
        if (Max_Accounts > size) {
            set[size] = account;
            size++;
        }
    }

    /*@
      @ public normal_behaviour
      @ requires account_number != null ;
      @ ensures \result == null || \result.getAccountNumber() == account_number ;
      @ diverges true;
      @*/
    public /*@ pure nullable @*/ UserAccount getAccount(String account_number) {
        int i = 0 ;
      /*@ loop_invariant i >= 0 && i <= size ;
        @ assignable i;
        @ decreases 0 < size - i ;
        @*/
        while(i < size) {
            if (set[i].getAccountNumber() == account_number) return set[i] ;
            i++;
        }         
        return null;
    }

    /*@
      @ public normal_behaviour
      @ ensures \result == size ;
      @*/
    public /*@ pure @*/ int getSize(){
           return size;
    }

    /*@
      @ public normal_behaviour
      @ ensures \result == set ;
      @*/
    public /*@ pure @*/ UserAccount[] getSet(){
           return set;
    }
}
