
int main()
{
  mapping ctx = ([
  "header": "Colors",
  "items": ({
      (["yes": 1, "name": "red", "first": true, "url": "#Red"]),
      (["yes": 0, "name": "green", "link": true, "url": "#Green"]),
      (["name": "blue", "link": true, "url": "#Blue"])
  }),
//  "empty": true
]);
  string t = Stdio.read_file("demo.mustache");

  object m = Public.Template.Mustache();
  write(m->to_html(t, ctx, (["url": "<li><a href=\"{{url}}\">{{name}}</a></li>"])));
  return 0;
}
