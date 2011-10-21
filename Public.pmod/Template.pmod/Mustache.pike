//! An implementation of the Mustache template format 
//! 
//! @note 
//!  the current implementation is not thread safe. Please use 
//!  a separate instance if the Mustache object for each rendering attempt. 
//! 
//! @note 
//!  by default, missing values (as opposed to "false" values such as zero) 
//!  will result in an empty string being inserted in the resulting output.
//!
//! @note 
//!  this module requires @[Regexp.PCRE]

/*
  mustache.pike -€” Logic-less templates in JavaScript
  based on mustache.js
  See http://mustache.github.com/ for more info.
*/

  constant version = "1.0";

  class _notfound{static mixed cast(string type){if(type=="string") return ""; else return 0;}};
  object notfound = _notfound();

  mapping regexCache = ([]);
  mixed Renderer;

  string otag = "{{";
  string ctag = "}}";
  mapping pragmas = ([]);
  array buffer = ({});
  mapping pragmas_implemented = ([
      "IMPLICIT-ITERATOR": true
      ]);
    
  mapping context = ([]);

  string render(string template, mapping context, mixed partials, int(0..1) in_recursion) {

      // reset buffer & set context
      if(!in_recursion) {
        buffer = ({}); // TODO: make this non-lazy
        this->context = context;
      }

      // fail fast
      if(!includes("", template)) {
        if(in_recursion) {
          return template;
        } else {
          send(template);
          return "";
        }
      }

      // get the pragmas together
      template = render_pragmas(template);

      // render the template
      string html = render_section(template, context, partials);

      // render_section did not find any sections, we still need to render the tags
      if (!html) {
        html = render_tags(template, context, partials, in_recursion);
      }

      if (in_recursion) {
        return html;
      } else {
        sendLines(html);
      }
    };

    /*
      Sends parsed lines
    */
    
    function send  = _send;
    
    void _send(string line) {
      if(line != "") {
        buffer+=({line});
      }
    }

    void sendLines(string text) {
      if (text) {
        array lines = text/"\n";
        foreach(lines;; string line)  
          send(line);
      }
    }

    /*
      Looks for %PRAGMAS
    */
    string render_pragmas(string template) {
      // no pragmas
      if(!includes("%", template)) {
        return template;
      }

      object regex = getCachedRegex("render_pragmas", lambda(string otag, string ctag) {
        return  PCRERegexp(otag + "%([\\w-]+) ?([\\w]+=[\\w]+)?" + ctag);
      });

      return regex->replace(template, lambda(string match, string pragma, mixed options) {
        if(!pragmas_implemented[pragma]) {
          throw(Error.Generic("This implementation of mustache doesn't understand the '" +
            pragma + "' pragma"));
        }
        pragmas[pragma] = ([]);
        if(options) {
          array opts = options/("=");
          pragmas[pragma][opts[0]] = opts[1];
        }
        return "";
        // ignore unknown pragmas silently
      });
    }

    /*
      Tries to find a partial in the curent scope and render it
    */
    string render_partial(string name, mapping context, mixed partials) {
      name = String.trim_whites(name);
      if(!partials || !partials[name] ) {
        throw(Error.Generic("unknown_partial '" + name + "'"));
      }
      if(!mappingp(context[name])) {
        return render(partials[name], context, partials, true);
      }
      return render(partials[name], context[name], partials, true);
    }

    /*
      Renders inverted (^) and normal (#) sections
    */
    string render_section(string template, mapping context, mapping partials) {
      if(!includes("#", template) && !includes("^", template)) {
        // did not render anything, there were no sections
        return 0;
      }
      object regex = getCachedRegex("render_section", lambda (string otag, string ctag) {
        // This regex matches _the first_ section ({{#foo}}{{/foo}}), and captures the remainder
        return PCRERegexp(
          "^([\\s\\S]*?)" +         // all the crap at the beginning that is not {{*}} ($1)

          otag +                    // {{
          "(\\^|\\#)\\s*(.+)\\s*" + //  #foo (# == $2, foo == $3)
          ctag +                    // }}

          "\n*([\\s\\S]*?)" +       // between the tag ($2). leading newlines are dropped

          otag +                    // {{
          "\\/\\s*\\3\\s*" +        //  /foo (backreference to the opening tag).
          ctag +                    // }}

          "\\s*([\\s\\S]*)$"       // everything else in the string ($4). leading whitespace is dropped.
          );
      });


      // for each {{#foo}}{{/foo}} section do...
      return regex->replace(template, lambda(mixed match, mixed parts){

        string before = parts[0];
        string type = parts[1];
        string name = parts[2];
        string content = parts[3];
        string after = parts[4];


        // before contains only tags, no sections
        string renderedBefore = before ? render_tags(before, context, partials, true) : "",

        // after may contain both sections and tags, so use full rendering function
        renderedAfter = after ? render(after, context, partials, true) : "",

        // will be computed below
        renderedContent;

        mixed value = find(name, context);
        if (type == "^") { // inverted section
          if (!value || arrayp(value) && sizeof(value) == 0) {
            // false or empty list, render it
            renderedContent = render(content, context, partials, true);
          } else {
            renderedContent = "";
          }
        } else if (type == "#") { // normal section
          if (arrayp(value)) { // Enumerable, Let's loop!
            renderedContent = map(value, lambda(mixed row) {
              return render(content, create_context(row), partials, true);
            })*("");
          } else if (mappingp(value)) { // Object, Use it as subcontext!
            renderedContent = render(content, create_context(value),
              partials, true);
          } else if (functionp(value)) {
            // higher order section
            renderedContent = value(context, content, lambda(mixed text) {
              return render(text, context, partials, true);
            });
          } else if(value == notfound || value == 0) // boolean false
            renderedContent = "";
            else if(value) // boolean
          {
            renderedContent = render(content, context, partials, true);
          }
          else {renderedContent = "";}
          
        }

        return renderedBefore + renderedContent + renderedAfter;
      });
    }


    /*
      Replace {{foo}} and friends with values from our view
    */
    string render_tags(mixed template, mapping context, mapping partials, int(0..1)in_recursion) {
  function new_regex= lambda()
  {
     return getCachedRegex("render_tags", lambda(string otag, string ctag) {
          return PCRERegexp(otag + "(=|!|>|\\{|%)?([^\\/#\\^]+?)\\1?" + ctag + "+");
        });
  };

    object regex = new_regex();

//   string tag_replace_callback(mixed match, string operator, string name) {
   string tag_replace_callback(string match, array submatches) {
      string operator = submatches[0];
      string name = submatches[1];

        switch(operator) {
        case "!": // ignore comments
          return "";
        case "=": // set new delimiters, rebuild the replace regexp
          set_delimiters(name);
          regex = new_regex();
          return "";
        case ">": // render partial
          return render_partial(name, context, partials);
        case "{": // the triple mustache is unescaped
          return find(name, context);
        default: // escape the value
          return escape((string)find(name, context));
        }
      };

      array lines = template/("\n");
      for(int i = 0; i < sizeof(lines); i++) {
        lines[i] = regex->replace(lines[i], tag_replace_callback);
        if(!in_recursion) {
          send(lines[i]);
        }
      }

      if(in_recursion) {
        return lines*("\n");
      }
    };

    mixed set_delimiters(string delimiters) {
      array dels = delimiters/(" ");
      otag = escape_regex(dels[0]);
      ctag = escape_regex(dels[1]);
    };
    
    mixed sRE;

    string escape_regex(string text) {
      // thank you Simon Willison
      if(!sRE) {
        array specials = ({
          "/", ".", "*", "+", "?", "|",
          "(", ")", "[", "]", "{", "}", "\\"
        });
        sRE = PCRERegexp(
          "(\\" + specials*("|\\") + ")"
        );
      }
      return sRE->replace(text, "\\$1");
    };

    // Checks whether a value is thruthy or false or 0
    int is_kinda_truthy(mixed bool) {
      return bool== 0 || bool;
    }

    /*
      find `name` in current `context`. That is find me a value
      from the view object
    */
    mixed find(string name, mapping context) {
      name = String.trim_whites(name);
      mixed value;

      // check for dot notation eg. foo.bar
      if(Regexp.PCRE.Plain("([a-z_]+)\." /*/ig*/)->match(name)){
        value = walk_context(name, context);
      }
      else{
        if(has_index(context, name)) {
	  value = context[name];
	} else if(has_index(this->context,name)) {
	  value = this->context[name];
	}
        else value = notfound; // rather than an ugly "0"
      }
      //write("%O\n", value);
//      if(name=="yes" && value == notfound) throw(Error.Generic("looking for yes in all the wrong places."));
      if(functionp(value)) {
        return value(context);
      }
      else
        return value;
    }

    mixed walk_context(string name, mapping context){
      array path = name/(".");
      // if the var doesn't exist in current context, check the top level context
      string pc;
      mixed value_context;
      if(has_index(context, path[0]))
        value_context = context;
      else value_context = this->context;
      [pc, path] = Array.shift(path);
      mixed value;
      if(has_index(value_context, pc))
        value = value_context[pc];
      else
        value = notfound;
      while(has_index(value_context, pc) && sizeof(path) > 0){

        value_context = value;
        [pc, path] = Array.shift(path);

        if(has_index(value_context, pc))
          value = value_context[pc];
        else
          value = notfound;
      }
      // if the value is a function, call it, binding the correct context
      if(functionp(value)) {
        return value(value_context);
      }
      else return value;
    }

    // Utility methods

    /* includes tag */
    int includes(mixed needle, mixed haystack) {
      return search(haystack, otag + needle) != -1;
    }

    /*
      Does away with nasty characters
    */
    string escape(string s) {
      if(!s) s = "";

      return PCRERegexp("&(?!\w+;)|[\"'\\\\<>]")->replace(s, lambda (string y) {
        switch(y) {
        case "&": return "&amp;";
        case "\"": return "&quot;";
        case "'": return "&#39;";
        case "<": return "&lt;";
        case ">": return "&gt;";
        default: return y;
      }});
    }

    // by @langalex, support for arrays of strings
    mixed create_context(mixed _context) {
      if(mappingp(_context)) {
        return _context;
      } else {
        string iterator = ".";
        if(this->pragmas["IMPLICIT-ITERATOR"]) {
          iterator = this->pragmas["IMPLICIT-ITERATOR"]->iterator;
        }
        mapping ctx = ([]);
        ctx[iterator] = _context;
        return ctx;
      }
    };

    mixed getCachedRegex(string name, mixed generator) {
      mixed byOtag = regexCache[this->otag];
      if (!byOtag) {
        byOtag = regexCache[this->otag] = ([]);
      }

      mixed byCtag = byOtag[this->ctag];
      if (!byCtag) {
        byCtag = byOtag[this->ctag] = ([]);
      }

      mixed regex = byCtag[name];
      if (!regex) {
        regex = byCtag[name] = generator(this->otag, this->ctag);
      }

      return regex;
    }


    //!  Turns a template and view into HTML
    mixed to_html(string template, mapping view, mapping|void partials, function|void send_fun) {
      object renderer = this_program();
      if(send_fun) {
        renderer->send = send_fun;
      }
      renderer->render(template, view || ([]), partials);
      if(!send_fun) {
        return renderer->buffer*("\n");
      }
    }
