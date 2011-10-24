//! A PCRE based Regular expression string replacer.

  protected object regexp;
  protected function split_fun;
  int max_iterations = 10;

  protected string _sprintf(mixed ... args)
  {
     return sprintf("PCRERegexp(%s)", regexp->pattern);
  }

//!
protected void create(string match) {
    regexp = Regexp.PCRE(match, Regexp.PCRE.OPTION.MULTILINE);
    split_fun = regexp->split;
  }

//! if with is a function, the first argument will be the total match
//! string, and the second argument will be an array of submatches
   string replace(string subject,string|function with, mixed|void ... args)
   {
    int i=0;
    String.Buffer res = String.Buffer();
                
    for (;;)
    {
      array(int)|int v=regexp->exec(subject,i);

      if (intp(v) && !regexp->handle_exec_error([int]v)) break;

      if (v[0]>i) res+=subject[i..v[0]-1];

      if 
        (stringp(with)) res+=with;
      else 
      { 
        array substrings = ({});
        if(sizeof(v)>2)
        {
          int c = 2;
          do
          {
             substrings += ({ subject[v[c]..(v[c+1]-1)] });
             c+=2;
          }
          while(c<= (sizeof(v)-2));
        }

        res += with(subject[v[0]..v[1]-1], substrings, @args); 
      }
      i=v[1];
    }

    res+=subject[i..];
    return res->get();
 }
