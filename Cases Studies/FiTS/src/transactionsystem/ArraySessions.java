package transactionsystem;

public class ArraySessions {
    static final protected /*@ spec_public @*/ int Max_Sessions = 20;

  /*@ public invariant
    @ set.length == Max_Sessions && set != null ;
    @*/  

    /*@ public invariant \typeof(set) == \type(Object[]) ; @*/    

    protected /*@ spec_public @*/ UserSession[] set;

  /*@ public invariant
    @ size >= 0 && size <= Max_Sessions 
      && (\forall int i ; i >= 0 && i < size ; set[i] != null) ;
    @*/
    protected /*@ spec_public @*/ int size;

    ArraySessions(){
        set = new UserSession[Max_Sessions];
        size = 0;
    }

    /*@
      @ public normal_behaviour
      @ requires session != null && Max_Sessions > size ;
      @ ensures size == \old(size) + 1 && set[\old(size)] == session ;
      @ assignable size,set[size] ;
      @ diverges true;
      @*/
    public void add(UserSession session) {
        if (Max_Sessions > size) {
            set[size] = session;
            size++;
        }
    }

    /*@
      @ public normal_behaviour
      @ ensures \result == null || \result.getId() == sid ;
      @ diverges true;
      @*/
    public /*@ pure nullable @*/ UserSession getSession(int sid) {
        int i = 0 ;
      /*@ loop_invariant i >= 0 && i <= size ;
        @ assignable i;
        @ decreases 0 < size - i ;
        @*/
        while(i < size) {
            if (set[i].getId() == sid) return set[i] ;
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
    public /*@ pure @*/ UserSession[] getSet(){
           return set;
    }
}
