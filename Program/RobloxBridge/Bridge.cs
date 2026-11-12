using System.Globalization;
using System.Text;

public enum BridgeKind{ Raw, Str, Ref }

public sealed class BridgeProp{
    public string Key   = "";
    public string Value = "";                 // для Str — уже без кавычек и escape
    public BridgeKind Kind = BridgeKind.Raw;

    public BridgeProp(){}
    public BridgeProp(string Key, string Value, BridgeKind Kind = BridgeKind.Raw){
        this.Key = Key; this.Value = Value; this.Kind = Kind;
    }
}

public sealed class BridgeNode{
    public string Class = "";
    public string Name  = "";
    public List<BridgeProp> Props    = [];    // включая Pivot и Source (скрипты)
    public List<BridgeProp> Attrs    = [];
    public List<string>     Tags     = [];
    public List<BridgeNode> Children = [];

    // Только между разбором файла и сборкой дерева (ссылки на другие файлы, пути от папки плейса)
    public string? AtFile;
    public string? AtSrc;

    public string? AtCode;     // только при записи: короткий скрипт остаётся в .bridge
    public string? SrcPath;    // только после ReadScene: @src ровно как написал пользователь
    public bool    WasCode;    // только после ReadScene: скрипт был записан как @code
    
    public string Origin = "";                // «файл:строка» для сообщений об ошибках

    public BridgeProp? Get(string Key) => Props.Find(P => P.Key == Key);
}

public static class Bridge{
    public const int    FormatVersion      = 1;
    public const string SceneDir           = "Scene";
    public const string ScriptsDir         = "Scripts";
    public const int    MapMaxPerLevel     = 40;
    public const string DefaultScriptExt   = "luau";
    public const int    DefaultInlineLines = 8;

    public static readonly string[] DefaultServices = [
        "Workspace", "Lighting", "MaterialService", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService",
        "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Teams", "SoundService"
    ];
    public static readonly string[] DefaultIgnore = ["Workspace/Camera"];

    private static readonly string[]     __PropFirst = ["Pivot", "Position", "Orientation", "Size"];
    private static readonly UTF8Encoding __Utf8      = new(false);
    private static readonly char[]       __BadChars  = Path.GetInvalidFileNameChars();

    // ======================================================================
    // Значения и пути

    /// Строка в кавычках с escape: \" \\ \n \r \t \uXXXX
    public static string Quote(string S){
        StringBuilder Sb = new(S.Length + 2);
        Sb.Append('"');

        foreach(char C in S){
            switch(C){
                case '"':  Sb.Append("\\\""); break;
                case '\\': Sb.Append("\\\\"); break;
                case '\n': Sb.Append("\\n");  break;
                case '\r': Sb.Append("\\r");  break;
                case '\t': Sb.Append("\\t");  break;
                default:
                    if(C < 0x20){ Sb.Append("\\u").Append(((int)C).ToString("x4")); }
                    else{         Sb.Append(C); }
                    break;
            }
        }

        return Sb.Append('"').ToString();
    }

    /// Число для записи: до 3 знаков, без хвостовых нулей, без «-0», всегда с точкой.
    public static string Num(double V){
        if(double.IsNaN(V) || double.IsInfinity(V)){ return "0"; }

        double R = Math.Round(V, 3);
        if(R == 0){ R = 0; }

        return R.ToString("0.###", CultureInfo.InvariantCulture);
    }

    /// Имя объекта как часть пути: «/» и «%» кодируются.
    public static string Seg(string Name) => Name.Replace("%", "%25").Replace("/", "%2F");

    // ======================================================================
    // Запись текста

    /// Пишет узлы в порядке, как они даны (сортировка — в WriteScene). Свойства пишутся в стабильном порядке.
    public static string Write(IEnumerable<BridgeNode> Nodes){
        StringBuilder Sb = new();
        foreach(BridgeNode N in Nodes){ __WriteNode(Sb, N, 0); }
        return Sb.ToString();
    }

    private static void __WriteNode(StringBuilder Sb, BridgeNode N, int Depth){
        string Pad = new(' ', Depth * 4);

        Sb.Append(Pad).Append(N.Class).Append(' ').Append(Quote(N.Name));

        if(N.AtSrc  != null){ Sb.Append(" @src=").Append(Quote(N.AtSrc)); }
        if(N.AtFile != null){ Sb.Append(" @file=").Append(Quote(N.AtFile)); }

        foreach(string T in N.Tags.OrderBy(T => T, StringComparer.Ordinal)){ Sb.Append(" #").Append(Quote(T)); }

        foreach(BridgeProp P in N.Props.OrderBy(P => { int I = Array.IndexOf(__PropFirst, P.Key); return I < 0 ? int.MaxValue : I; })
                                 .ThenBy(P => P.Key, StringComparer.Ordinal)){
            __WriteProp(Sb, "", P);
        }

        foreach(BridgeProp P in N.Attrs.OrderBy(P => P.Key, StringComparer.Ordinal)){ __WriteProp(Sb, "$", P); }

        if(N.AtCode != null){ // блок кода всегда последний на строке
            Sb.Append(" @code=<<<\n");

            foreach(string Line in N.AtCode.Split('\n')){
                if(Line.Length > 0){ Sb.Append(Pad).Append("    ").Append(Line); }
                Sb.Append('\n');
            }

            Sb.Append(Pad).Append(">>>");
        }

        if(N.AtFile == null && N.Children.Count > 0){
            Sb.Append(" {\n");
            foreach(BridgeNode C in N.Children){ __WriteNode(Sb, C, Depth + 1); }
            Sb.Append(Pad).Append("}\n");
        }else{
            Sb.Append('\n');
        }
    }

    private static void __WriteProp(StringBuilder Sb, string Prefix, BridgeProp P){
        Sb.Append(' ').Append(Prefix);
        Sb.Append(P.Key.Length > 0 && P.Key.All(C => char.IsAsciiLetterOrDigit(C) || C == '_') ? P.Key : Quote(P.Key));

        switch(P.Kind){
            case BridgeKind.Str: Sb.Append('=').Append(Quote(P.Value));       break;
            case BridgeKind.Ref: Sb.Append("=@").Append(Quote(P.Value));      break;
            default:
                if(P.Value == "true"){ break; } // голый флаг

                if(P.Value.Length == 0 || P.Value.Any(C => char.IsWhiteSpace(C) || C == '"' || C == '{' || C == '}')){
                    throw new FormatException($"Значение «{P.Key}» нельзя записать без кавычек: «{P.Value}»");
                }

                Sb.Append('=').Append(P.Value);
                break;
        }
    }

    // ======================================================================
    // Разбор текста (одна строка — один объект)

    public static List<BridgeNode> Parse(string Text, string FileName, List<string> Problems){
        List<BridgeNode>  Roots = [];
        Stack<BridgeNode> Open  = new();
        string[] Lines = Text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');

        for(int I = 0; I < Lines.Length; I++){
            string Trim = Lines[I].TrimEnd();

            // Блок: ... @code=<<<  строки  >>>
            if(Trim.EndsWith("@code=<<<")){
                int          First  = I;
                List<string> Body   = [];
                string       Tail   = "";
                bool         Closed = false;

                I++;
                while(I < Lines.Length){
                    string T = Lines[I].TrimStart();
                    if(T.StartsWith(">>>")){ Tail = T.Substring(3); Closed = true; break; }

                    Body.Add(Lines[I]);
                    I++;
                }

                if(!Closed){ Problems.Add($"{FileName}:{First + 1}: блок @code=<<< не закрыт (нужна строка >>>)"); }

                string Joined = Trim.Substring(0, Trim.Length - 3) + Quote(__Dedent(Body)) + Tail;
                __ParseLine(Joined, First + 1, FileName, Roots, Open, Problems);
                continue;
            }

            __ParseLine(Lines[I], I + 1, FileName, Roots, Open, Problems);
        }

        foreach(BridgeNode N in Open){
            Problems.Add($"{N.Origin}: не закрыта «{{» у {N.Class} \"{N.Name}\"");
        }

        return Roots;
    }

    /// Срезает общий отступ у строк блока кода.
    private static string __Dedent(List<string> L){
        int Min = int.MaxValue;

        foreach(string S in L){
            if(S.Trim().Length == 0){ continue; }

            int N = 0;
            while(N < S.Length && (S[N] == ' ' || S[N] == '\t')){ N++; }
            Min = Math.Min(Min, N);
        }

        if(Min == int.MaxValue){ Min = 0; }
        return string.Join("\n", L.Select(S => S.Length >= Min ? S.Substring(Min) : S.TrimStart()));
    }

    private static void __ParseLine(string L, int No, string FileName, List<BridgeNode> Roots, Stack<BridgeNode> Open, List<string> Problems){
        string Where = $"{FileName}:{No}";
        int P = 0;

        __Skip(L, ref P);
        if(P >= L.Length || __IsComment(L, P)){ return; }

        if(L[P] == '}'){
            P++;
            __Skip(L, ref P);

            if(P < L.Length && !__IsComment(L, P)){ Problems.Add($"{Where}: после «}}» ничего не должно быть"); }

            if(Open.Count == 0){ Problems.Add($"{Where}: лишняя «}}»"); }
            else{                Open.Pop(); }

            return;
        }

        BridgeNode N = new(){ Origin = Where };
        bool Opens = false, Bad = false;

        N.Class = __Word(L, ref P);
        __Skip(L, ref P);

        if(N.Class.Length == 0 || P >= L.Length || L[P] != '"'){
            Problems.Add($"{Where}: ожидается «Класс \"Имя\"» (имя всегда в кавычках)");
            Bad = true;
        }else{
            string? Name = __Str(L, ref P);

            if(Name == null){ Problems.Add($"{Where}: строка не закрыта или неверный escape"); Bad = true; }
            else{             N.Name = Name; }
        }

        while(!Bad){
            __Skip(L, ref P);
            if(P >= L.Length || __IsComment(L, P)){ break; }

            char C = L[P];

            if(C == '{'){
                Opens = true;
                P++;
                __Skip(L, ref P);

                if(P < L.Length && !__IsComment(L, P)){ Problems.Add($"{Where}: после «{{» ничего не должно быть"); }
                break;
            }

            if(C == '#'){
                P++;
                string? Tag = P < L.Length && L[P] == '"' ? __Str(L, ref P) : null;

                if(Tag == null){ Problems.Add($"{Where}: тег пишется как #\"Имя\""); Bad = true; break; }

                N.Tags.Add(Tag);
                continue;
            }

            if(C == '@'){
                P++;
                string  Key = __Word(L, ref P);
                string? V   = null;

                if(P + 1 < L.Length && L[P] == '=' && L[P + 1] == '"'){ P++; V = __Str(L, ref P); }

                if(V == null){ Problems.Add($"{Where}: ожидается @{Key}=\"путь\""); Bad = true; break; }

                if(Key == "src"){       N.AtSrc  = V; }
                else if(Key == "code"){
                    N.WasCode = true;
                    N.Props.RemoveAll(P => P.Key == "Source");
                    N.Props.Add(new BridgeProp("Source", V, BridgeKind.Str));
                }
                else if(Key == "file"){ N.AtFile = V; }
                else{                   Problems.Add($"{Where}: неизвестная директива @{Key}"); }

                continue;
            }

            bool IsAttr = C == '$';
            if(IsAttr){ P++; }

            string PropKey = P < L.Length && L[P] == '"' ? (__Str(L, ref P) ?? "") : __Word(L, ref P);

            if(PropKey.Length == 0){ Problems.Add($"{Where}: непонятный символ «{C}»"); Bad = true; break; }

            BridgeProp Pr = new(){ Key = PropKey, Value = "true" };

            if(P < L.Length && L[P] == '='){
                P++;

                if(P >= L.Length || char.IsWhiteSpace(L[P])){ Problems.Add($"{Where}: нет значения после «=» у {PropKey}"); Bad = true; break; }

                if(L[P] == '"'){
                    string? V = __Str(L, ref P);
                    if(V == null){ Problems.Add($"{Where}: строка не закрыта или неверный escape ({PropKey})"); Bad = true; break; }

                    Pr.Value = V;
                    Pr.Kind  = BridgeKind.Str;
                }else if(L[P] == '@' && P + 1 < L.Length && L[P + 1] == '"'){
                    P++;
                    string? V = __Str(L, ref P);
                    if(V == null){ Problems.Add($"{Where}: строка не закрыта или неверный escape ({PropKey})"); Bad = true; break; }

                    Pr.Value = V;
                    Pr.Kind  = BridgeKind.Ref;
                }else{
                    Pr.Value = __Raw(L, ref P);
                }
            }

            (IsAttr ? N.Attrs : N.Props).Add(Pr);
        }

        if(Bad && L.TrimEnd().EndsWith('{')){ Opens = true; } // чтобы одна ошибка не сбила скобки всего файла

        if(Open.Count > 0){ Open.Peek().Children.Add(N); }
        else{               Roots.Add(N); }

        if(Opens){ Open.Push(N); }
    }

    private static void __Skip(string L, ref int P){
        while(P < L.Length && (L[P] == ' ' || L[P] == '\t')){ P++; }
    }

    private static bool __IsComment(string L, int P) => P + 1 < L.Length && L[P] == '/' && L[P + 1] == '/';

    private static string __Word(string L, ref int P){
        int S = P;
        while(P < L.Length && !char.IsWhiteSpace(L[P]) && L[P] != '=' && L[P] != '"' && L[P] != '{' && L[P] != '}'){ P++; }
        return L.Substring(S, P - S);
    }

    private static string __Raw(string L, ref int P){
        int S = P;
        while(P < L.Length && !char.IsWhiteSpace(L[P])){ P++; }
        return L.Substring(S, P - S);
    }

    /// Читает строку, L[P] == '"'. null — не закрыта или неверный escape.
    private static string? __Str(string L, ref int P){
        StringBuilder Sb = new();
        P++;

        while(P < L.Length){
            char C = L[P++];

            if(C == '"'){ return Sb.ToString(); }
            if(C != '\\'){ Sb.Append(C); continue; }
            if(P >= L.Length){ break; }

            char E = L[P++];

            switch(E){
                case 'n':  Sb.Append('\n'); break;
                case 'r':  Sb.Append('\r'); break;
                case 't':  Sb.Append('\t'); break;
                case '\\': Sb.Append('\\'); break;
                case '"':  Sb.Append('"');  break;
                case 'u':
                    if(P + 4 > L.Length || !int.TryParse(L.AsSpan(P, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int Code)){
                        P = L.Length;
                        return null;
                    }

                    Sb.Append((char)Code);
                    P += 4;
                    break;
                default:
                    P = L.Length;
                    return null;
            }
        }

        P = L.Length;
        return null;
    }

    // ======================================================================
    // Пути, индекс, фильтр

    private static string[] __SiblingPaths(List<BridgeNode> L, string Parent){
        string[] R = new string[L.Count];
        Dictionary<string, int> Seen = new();

        for(int I = 0; I < L.Count; I++){
            string S = Seg(L[I].Name);

            Seen[S] = Seen.GetValueOrDefault(S) + 1;
            if(Seen[S] > 1){ S += "~" + Seen[S]; }

            R[I] = Parent.Length == 0 ? S : Parent + "/" + S;
        }

        return R;
    }

    /// Путь объекта -> объект (для ссылок, валидатора, diff).
    public static Dictionary<string, BridgeNode> Index(List<BridgeNode> Roots){
        Dictionary<string, BridgeNode> R = new();
        __Index(Roots, "", R);
        return R;
    }

    private static void __Index(List<BridgeNode> L, string Parent, Dictionary<string, BridgeNode> R){
        string[] Paths = __SiblingPaths(L, Parent);

        for(int I = 0; I < L.Count; I++){
            R[Paths[I]] = L[I];
            __Index(L[I].Children, Paths[I], R);
        }
    }

    private static List<BridgeNode> __Sorted(IEnumerable<BridgeNode> L){
        return L.OrderBy(N => N.Name, StringComparer.Ordinal).ThenBy(N => N.Class, StringComparer.Ordinal).ToList(); // OrderBy стабилен
    }

    private static void __SortTree(List<BridgeNode> L){
        List<BridgeNode> S = __Sorted(L);

        L.Clear();
        L.AddRange(S);

        foreach(BridgeNode N in L){ __SortTree(N.Children); }
    }

    /// Оставляет только выбранные сервисы (в заданном порядке) и убирает пути из Ignore вместе с потомками.
    /// Сначала сортирует дерево, чтобы «~2» в путях совпадали с теми, что видит пользователь.
    public static List<BridgeNode> Filter(List<BridgeNode> Roots, IEnumerable<string> Services, IEnumerable<string> Ignore){
        __SortTree(Roots);

        List<BridgeNode> Kept = [];
        foreach(string S in Services){
            BridgeNode? R = Roots.Find(N => N.Class == S);
            if(R != null){ Kept.Add(R); }
        }

        __Prune(Kept, "", new HashSet<string>(Ignore));
        return Kept;
    }

    private static void __Prune(List<BridgeNode> L, string Parent, HashSet<string> Ign){
        string[] Paths = __SiblingPaths(L, Parent);
        List<BridgeNode> Keep = [];

        for(int I = 0; I < L.Count; I++){
            if(Ign.Contains(Paths[I])){ continue; }

            __Prune(L[I].Children, Paths[I], Ign);
            Keep.Add(L[I]);
        }

        L.Clear();
        L.AddRange(Keep);
    }

    // ======================================================================
    // Запись сцены на диск

    /// Считает строки и помечает в Splits поддеревья, которые не влезают в лимит. Возвращает размер списка в строках.
    private static int __Measure(List<BridgeNode> L, string Parent, Dictionary<string, string> Splits, int Limit, bool Top){
        string[] Paths = __SiblingPaths(L, Parent);
        int Total = 0;

        for(int I = 0; I < L.Count; I++){
            BridgeNode N = L[I];
            int Own = 1;

            if(N.Children.Count > 0){
                int  Inner   = __Measure(N.Children, Paths[I], Splits, Limit, false);
                bool IsSplit = Splits.ContainsKey(Paths[I]);

                if(!IsSplit){ Own += Inner + 1; }

                if(!Top && !IsSplit && Limit > 0 && Own > Limit){
                    Splits[Paths[I]] = __DefaultFile(Paths[I]);
                    Own = 1;
                }
            }

            Total += Own;
        }

        return Total;
    }

    private static string __DefaultFile(string NodePath) => $"{SceneDir}/{__FileSegs(NodePath)}.bridge";

    private static string __FileSeg(string S){
        StringBuilder Sb = new();
        foreach(char C in S){ Sb.Append(Array.IndexOf(__BadChars, C) >= 0 ? '_' : C); }

        string R = Sb.ToString().TrimEnd('.', ' ');
        return R.Length == 0 ? "_" : R;
    }

    private static string __FileSegs(string NodePath) => string.Join('/', NodePath.Split('/').Select(__FileSeg));

    private static void __WriteIfChanged(string Full, string Text){
        Directory.CreateDirectory(Path.GetDirectoryName(Full)!);

        if(!File.Exists(Full) || File.ReadAllText(Full) != Text){
            File.WriteAllText(Full, Text, __Utf8);
        }
    }
    
        private sealed class WriteCtx{
        public string Root    = "";
        public string Project = "";
        public string ScriptExt   = DefaultScriptExt;
        public int    InlineLines = DefaultInlineLines;

        public Dictionary<string, string>     Splits = [];
        public Dictionary<string, string>     Files  = new(StringComparer.OrdinalIgnoreCase); // полный путь -> текст
        public Dictionary<string, BridgeNode> Old    = [];                                     // что лежало на диске до записи
        public HashSet<string>                Seen   = [];
        public List<string>                   Warnings = [];
    }

    /// Раскладывает дерево по файлам и пишет на диск (только изменившиеся файлы, лишние в Scene/ и Scripts/ удаляются).
    /// Splits дополняется автоматическими выносами — после вызова сохрани его в place.json.
    /// ScriptExt — расширение НОВЫХ скриптов (luau/lua); у существующих путь @src сохраняется как есть.
    /// InlineLines — до скольких строк новый скрипт остаётся @code (0 = всегда в файл).
    public static void WriteScene(string PlaceDir, List<BridgeNode> Roots, Dictionary<string, string> Splits, int AutoSplitLines, List<string> Warnings,
                                  string ScriptExt = DefaultScriptExt, int InlineLines = DefaultInlineLines){
        string Root = Path.GetFullPath(PlaceDir);
        __SortTree(Roots);

        string Ext = (ScriptExt ?? "").Trim().TrimStart('.').ToLowerInvariant();
        if(Ext != "lua" && Ext != "luau"){
            if(Ext.Length > 0){ Warnings.Add($"place.json: ScriptExt «{ScriptExt}» не подходит (нужно luau или lua), использую {DefaultScriptExt}"); }
            Ext = DefaultScriptExt;
        }

        WriteCtx Ctx = new(){
            Root = Root, Project = ProjectRoot(Root), ScriptExt = Ext, InlineLines = InlineLines,
            Splits = Splits, Warnings = Warnings, Old = __ReadOld(Root)
        };

        __Measure(Roots, "", Splits, AutoSplitLines, true);

        string[] RootPaths = __SiblingPaths(Roots, "");
        var RootFiles = new (string Rel, string Full)[Roots.Count];

        for(int I = 0; I < Roots.Count; I++){
            RootFiles[I] = __Reserve(Ctx, null, $"{SceneDir}/{__FileSeg(Roots[I].Name)}.bridge", Roots[I].Name);
        }

        for(int I = 0; I < Roots.Count; I++){
            BridgeNode Clone = __Emit(Roots[I], RootPaths[I], Ctx);
            Ctx.Files[RootFiles[I].Full] = Write([Clone]);
        }

        foreach(string K in Splits.Keys){
            if(!Ctx.Seen.Contains(K)){ Warnings.Add($"Splits: объект «{K}» не найден (переименован или удалён?)"); }
        }

        foreach(var (Full, Text) in Ctx.Files){ __WriteIfChanged(Full, Text); }

        HashSet<string> Keep = new(StringComparer.OrdinalIgnoreCase);
        foreach(string Full in Ctx.Files.Keys){
            string Rel = Path.GetRelativePath(Root, Full).Replace('\\', '/');
            if(!Rel.StartsWith("..") && !Path.IsPathRooted(Rel)){ Keep.Add(Rel); } // файлы вне плейса не чистим
        }

        __Clean(Root, SceneDir,   [".bridge"],          Keep);
        __Clean(Root, ScriptsDir, [".luau", ".lua"],    Keep);
    }

    /// Что сейчас лежит на диске (только пути @src и признак @code, без чтения скриптов).
    private static Dictionary<string, BridgeNode> __ReadOld(string Root){
        try{
            List<BridgeNode> Old = ReadScene(Root, [], null, true);
            __SortTree(Old);
            return Index(Old);
        }catch{
            return [];
        }
    }

    /// Резервирует файл. Wanted — путь, который уже был у объекта (сохраняется как написан).
    /// Если он недопустим или занят другим объектом — берётся Default (с «~2», если надо).
    private static (string Rel, string Full) __Reserve(WriteCtx Ctx, string? Wanted, string Default, string Owner){
        if(Wanted != null){
            string? Full = ResolvePath(Ctx.Root, Wanted, out _);

            if(Full != null && !Ctx.Files.ContainsKey(Full)){
                Ctx.Files[Full] = "";

                if(!IsInside(Ctx.Project, Full)){ Ctx.Warnings.Add($"{Owner}: файл вне проекта: {Wanted}"); }
                return (Wanted, Full);
            }

            Ctx.Warnings.Add(Full == null
                ? $"{Owner}: недопустимый путь «{Wanted}», использую стандартное имя"
                : $"{Owner}: файл «{Wanted}» уже занят другим объектом, использую стандартное имя");
        }

        string Ext  = Path.GetExtension(Default);
        string Stem = Default.Substring(0, Default.Length - Ext.Length);
        string R    = Default;
        int    K    = 2;

        while(true){
            string F = Path.GetFullPath(Path.Combine(Ctx.Root, R)).Replace('\\', '/');

            if(!Ctx.Files.ContainsKey(F)){
                Ctx.Files[F] = "";
                return (R, F);
            }

            R = $"{Stem}~{K++}{Ext}";
        }
    }

    private static bool __IsSceneTop(string Root, string Full){
        string Scene = Path.GetFullPath(Path.Combine(Root, SceneDir)).Replace('\\', '/').TrimEnd('/');
        string Dir   = (Path.GetDirectoryName(Full) ?? "").Replace('\\', '/').TrimEnd('/');
        return string.Equals(Scene, Dir, StringComparison.OrdinalIgnoreCase);
    }

    private static BridgeNode __Emit(BridgeNode N, string NodePath, WriteCtx Ctx){
        Ctx.Seen.Add(NodePath);

        BridgeNode C = new(){ Class = N.Class, Name = N.Name, Tags = N.Tags, Attrs = N.Attrs, Props = [..N.Props] };

        BridgeProp? Src = N.Get("Source");
        if(Src != null && Src.Kind == BridgeKind.Str){
            Ctx.Old.TryGetValue(NodePath, out BridgeNode? Old);

            string? Wanted = Old?.SrcPath;   // уже был файл — путь не трогаем
            bool    Inline = false;

            if(Wanted == null){
                Inline = FitsInline(Src.Value, Ctx.InlineLines);

                if(!Inline && Old != null && Old.WasCode){
                    Ctx.Warnings.Add($"{NodePath}: скрипт больше не помещается в @code, вынесен в файл");
                }
            }

            C.Props.RemoveAll(P => P.Key == "Source");

            if(Inline){
                C.AtCode = Src.Value;
            }else{
                var (Rel, Full) = __Reserve(Ctx, Wanted, $"{ScriptsDir}/{__FileSegs(NodePath)}.{Ctx.ScriptExt}", NodePath);

                Ctx.Files[Full] = Src.Value;
                C.AtSrc = Rel;
            }
        }

        List<BridgeNode> Kids  = [];
        string[]         Paths = __SiblingPaths(N.Children, NodePath);

        for(int I = 0; I < N.Children.Count; I++){ Kids.Add(__Emit(N.Children[I], Paths[I], Ctx)); }

        if(Ctx.Splits.TryGetValue(NodePath, out string? Target) && Kids.Count > 0){
            string? Check = ResolvePath(Ctx.Root, Target, out _);
            bool    Ok    = Check != null && Check.EndsWith(".bridge", StringComparison.OrdinalIgnoreCase) && !__IsSceneTop(Ctx.Root, Check);

            if(!Ok){
                Ctx.Warnings.Add($"Splits: «{Target}» для {NodePath} — нужен путь к файлу .bridge (не прямо в Scene/). Использую стандартное имя.");
                Target = __DefaultFile(NodePath);
                Ctx.Splits[NodePath] = Target;
            }

            var (FileRel, FileFull) = __Reserve(Ctx, Target, __DefaultFile(NodePath), NodePath);
            if(FileRel != Target){ Ctx.Splits[NodePath] = FileRel; }

            Ctx.Files[FileFull] = Write(Kids);
            C.AtFile = FileRel;
        }else{
            C.Children = Kids;
        }

        return C;
    }

    private static void __Clean(string Root, string Dir, string[] Exts, HashSet<string> Keep){
        string D = Path.Combine(Root, Dir);
        if(!Directory.Exists(D)){ return; }

        foreach(string F in Directory.EnumerateFiles(D, "*", SearchOption.AllDirectories)){
            if(!Exts.Any(E => F.EndsWith(E, StringComparison.OrdinalIgnoreCase))){ continue; }

            string Rel = Path.GetRelativePath(Root, F).Replace('\\', '/');
            if(!Keep.Contains(Rel)){ File.Delete(F); }
        }

        foreach(string Sub in Directory.EnumerateDirectories(D, "*", SearchOption.AllDirectories).OrderByDescending(S => S.Length).ToList()){
            if(!Directory.EnumerateFileSystemEntries(Sub).Any()){ Directory.Delete(Sub); }
        }
    }

    // ======================================================================
    // Чтение сцены с диска

       /// Читает Scene/*.bridge (по файлу на сервис), подтягивает @file и @src (пути относительные или полные).
    /// Warnings (необязательно) — замечания вроде «файл вне проекта». Light — не читать тексты скриптов.
    public static List<BridgeNode> ReadScene(string PlaceDir, List<string> Problems, List<string>? Warnings = null, bool Light = false){
        string Root  = Path.GetFullPath(PlaceDir);
        string Scene = Path.Combine(Root, SceneDir);

        List<BridgeNode> Roots   = [];
        HashSet<string>  Visited = new(StringComparer.OrdinalIgnoreCase);

        if(!Directory.Exists(Scene)){ return Roots; }

        foreach(string F in Directory.EnumerateFiles(Scene, "*.bridge", SearchOption.TopDirectoryOnly).OrderBy(F => F, StringComparer.OrdinalIgnoreCase)){
            string Rel = Path.GetRelativePath(Root, F).Replace('\\', '/');
            Visited.Add(Rel);

            List<BridgeNode> Part = Parse(File.ReadAllText(F), Rel, Problems);
            __Resolve(Part, Root, Visited, Problems, Warnings, Light);
            Roots.AddRange(Part);
        }

        foreach(string F in Directory.EnumerateFiles(Scene, "*.bridge", SearchOption.AllDirectories)){
            string Rel = Path.GetRelativePath(Root, F).Replace('\\', '/');
            if(!Visited.Contains(Rel)){ Problems.Add($"{Rel}: файл не подключён ни одним @file (будет удалён при следующем Pull)"); }
        }

        return Roots;
    }

    private static void __Resolve(List<BridgeNode> L, string Root, HashSet<string> Visited, List<string> Problems, List<string>? Warnings, bool Light){
        string Project = ProjectRoot(Root);

        foreach(BridgeNode N in L){
            if(N.AtSrc != null){
                N.SrcPath = N.AtSrc;
                string? Full = ResolvePath(Root, N.AtSrc, out string Err);

                if(Full == null){ Problems.Add($"{N.Origin}: {Err} (@src)"); }
                else{
                    if(Warnings != null && !IsInside(Project, Full)){ Warnings.Add($"{N.Origin}: файл вне проекта: {N.AtSrc}"); }

                    if(!Light){
                        if(!File.Exists(Full)){ Problems.Add($"{N.Origin}: файл @src не найден: {N.AtSrc}"); }
                        else{
                            N.Props.RemoveAll(X => X.Key == "Source");
                            N.Props.Add(new BridgeProp("Source", File.ReadAllText(Full), BridgeKind.Str));
                        }
                    }
                }

                N.AtSrc = null;
            }

            __Resolve(N.Children, Root, Visited, Problems, Warnings, Light); // дети, написанные в скобках

            if(N.AtFile != null){
                string? Full = ResolvePath(Root, N.AtFile, out string Err);

                if(Full == null){            Problems.Add($"{N.Origin}: {Err} (@file)"); }
                else if(!File.Exists(Full)){ Problems.Add($"{N.Origin}: файл @file не найден: {N.AtFile}"); }
                else if(!Visited.Add(Path.GetRelativePath(Root, Full).Replace('\\', '/'))){
                    Problems.Add($"{N.Origin}: файл {N.AtFile} подключён повторно (цикл или дубль)");
                }else{
                    if(Warnings != null && !IsInside(Project, Full)){ Warnings.Add($"{N.Origin}: файл вне проекта: {N.AtFile}"); }
                    if(N.Children.Count > 0){ Problems.Add($"{N.Origin}: у объекта и «{{ }}», и @file — оставьте одно"); }

                    List<BridgeNode> Kids = Parse(File.ReadAllText(Full), N.AtFile, Problems);
                    __Resolve(Kids, Root, Visited, Problems, Warnings, Light);
                    N.Children.AddRange(Kids);
                }

                N.AtFile = null;
            }
        }
    }

    /// Путь: относительный (от BaseDir, можно ../) или полный. Всегда возвращает полный путь с «/».
    public static string? ResolvePath(string BaseDir, string Raw, out string Error){
        Error = "";
        string P = Raw.Trim().Replace('\\', '/');
        if(P == ""){ Error = "пустой путь"; return null; }

        try{
            string Full = Path.IsPathRooted(P) ? P : Path.Combine(BaseDir, P);
            return Path.GetFullPath(Full).Replace('\\', '/');
        }catch{
            Error = "недопустимый путь: " + Raw;
            return null;
        }
    }

    public static bool IsInside(string Dir, string Full){
        string D = Path.GetFullPath(Dir).Replace('\\', '/').TrimEnd('/') + "/";
        return Full.Replace('\\', '/').StartsWith(D, StringComparison.OrdinalIgnoreCase);
    }

    /// Корень проекта по папке плейса (Places/<папка> -> на два уровня выше).
    public static string ProjectRoot(string PlaceDir) => Path.GetFullPath(Path.Combine(PlaceDir, "..", ".."));

    /// Можно ли записать скрипт как @code без потерь (иначе при Push вечно было бы «~ Source»).
    public static bool FitsInline(string Text, int MaxLines){
        if(MaxLines <= 0 || Text.Length > 400 || Text.Contains(">>>")){ return false; }
        if(Text.Length > 0 && Text[^1] == '\n'){ return false; }

        string[] Lines = Text.Split('\n');
        if(Lines.Length > MaxLines){ return false; }

        int Min = int.MaxValue;

        foreach(string L in Lines){
            foreach(char C in L){ if(C < 0x20 && C != '\t'){ return false; } } // в т.ч. \r
            if(L.Length == 0){ continue; }
            if(L.Trim().Length == 0){ return false; }

            int N = 0;
            while(N < L.Length && (L[N] == ' ' || L[N] == '\t')){ N++; }
            Min = Math.Min(Min, N);
        }

        return Min == int.MaxValue || Min == 0; // общий отступ при чтении срезался бы
    }

    // ======================================================================
    // Проверка

    /// KnownProp(Класс, Свойство) — по схеме; null, если схему проверять не нужно.
    public static List<string> Validate(List<BridgeNode> Roots, Func<string, string, bool>? KnownProp = null){
        List<string> R = [];
        Dictionary<string, BridgeNode> Idx = Index(Roots);

        foreach(var (NodePath, N) in Idx){
            string W = N.Origin.Length > 0 ? N.Origin : NodePath;

            if(N.Class.Length == 0){ R.Add($"{W}: пустой класс"); }
            if(N.Name.Length  == 0){ R.Add($"{W}: пустое имя"); }

            HashSet<string> Keys = [];

            foreach(BridgeProp P in N.Props){
                if(!Keys.Add(P.Key)){ R.Add($"{W}: свойство {P.Key} указано дважды"); }

                if(KnownProp != null && P.Key != "Pivot" && !KnownProp(N.Class, P.Key)){
                    R.Add($"{W}: у {N.Class} нет свойства {P.Key} (будет проигнорировано)");
                }

                if(P.Kind == BridgeKind.Ref && !Idx.ContainsKey(P.Value)){
                    R.Add($"{W}: ссылка {P.Key} указывает на несуществующий объект {P.Value}");
                }
            }

            HashSet<string> AttrKeys = [];
            foreach(BridgeProp A in N.Attrs){
                if(!AttrKeys.Add(A.Key)){ R.Add($"{W}: атрибут ${A.Key} указан дважды"); }
            }
        }

        return R;
    }

    // ======================================================================
    // _map.txt и AGENTS.md

    public static string Map(List<BridgeNode> Roots, Dictionary<string, string> Splits, int MaxDepth = 3){
        StringBuilder Sb = new();

        Sb.Append("# Карта сцены (создаётся приложением, не править)\n");
        Sb.Append("# Класс \"Имя\"  [файл]  (+N — скрытых объектов внутри)\n\n");

        __Map(Sb, Roots, "", 0, MaxDepth, Splits);
        return Sb.ToString();
    }

    private static void __Map(StringBuilder Sb, List<BridgeNode> L, string Parent, int Level, int Max, Dictionary<string, string> Splits){
        string[] Paths = __SiblingPaths(L, Parent);
        int Shown = Math.Min(L.Count, MapMaxPerLevel);

        for(int I = 0; I < Shown; I++){
            BridgeNode N = L[I];

            Sb.Append(' ', Level * 2).Append(N.Class).Append(' ').Append(Quote(N.Name));

            if(Level == 0){                                      Sb.Append($"  [{SceneDir}/{__FileSeg(N.Name)}.bridge]"); }
            else if(Splits.TryGetValue(Paths[I], out string? F)){ Sb.Append($"  [{F}]"); }

            int Hidden = __Count(N.Children);
            if(Hidden > 0 && Level + 1 >= Max){ Sb.Append($"  (+{Hidden})"); }

            Sb.Append('\n');

            if(Level + 1 < Max){ __Map(Sb, N.Children, Paths[I], Level + 1, Max, Splits); }
        }

        if(L.Count > Shown){ Sb.Append(' ', Level * 2).Append($"… ещё {L.Count - Shown}\n"); }
    }

    private static int __Count(List<BridgeNode> L){
        int N = L.Count;
        foreach(BridgeNode C in L){ N += __Count(C.Children); }
        return N;
    }

    /// _map.txt всегда обновляется.
    public static void WriteMeta(string PlaceDir, List<BridgeNode> Roots, Dictionary<string, string> Splits){
        __WriteIfChanged(Path.Combine(PlaceDir, "_map.txt"), Map(Roots, Splits));
    }
    
    /// Пишет AGENTS.md в корень проекта (рядом с bridge.json).
    /// Force=false — только если файла нет. Возвращает true, если файл записан.
    public static bool WriteAgents(string ProjectDir, bool Force = false){
        string Full = Path.Combine(ProjectDir, "AGENTS.md");
        if(!Force && File.Exists(Full)){ return false; }

        Directory.CreateDirectory(ProjectDir);
        File.WriteAllText(Full, AgentsText, __Utf8);
        return true;
    }

    public const string AgentsText = """
# RobloxBridge: инструкция для ИИ

Эта папка — проект Roblox в текстовом формате .bridge. Приложение RobloxBridge переносит плейсы в Studio и обратно кнопками Pull (Studio → файлы) и Push (файлы → Studio). Перед применением пользователь видит diff. Git ведёт пользователь, ты его не трогаешь.

Главное правило: **файлы — источник истины для синхронизируемых сервисов**. Если удалить объект из .bridge, при Push он удалится в Studio. Не удаляй и не переписывай то, о чём тебя не просили.

## Структура проекта
- `bridge.json` — описание проекта, список плейсов. Не правь.
- `Prefabs/<Имя>.bridge` — префабы (шаблоны объектов), общие для всех плейсов.
- `Places/<папка>/` — один плейс (по умолчанию папка названа по PlaceId). Все пути ниже (`Scene/`, `Scripts/`, `Geometry/`) считаются от этой папки. Работай только с тем плейсом, о котором просят.

## Структура плейса
- `Scene/<Сервис>.bridge` — по одному файлу на сервис (Workspace, Lighting, ReplicatedStorage, ...).
- `Scene/<Сервис>/...bridge` — вынесенные поддеревья, подключаются директивой `@file`.
- `Scripts/<путь объекта>.lua` — тексты скриптов, подключаются директивой `@src`.
- `Geometry/<хеш>.bin` — геометрия юнионов. Бинарные файлы, не открывай и не изменяй.
- `Terrain.voxels` — воксели террейна. Бинарный файл, не трогай.
- `_map.txt` — обзор дерева (генерируется, не править). `place.json` — настройки (Services, Ignore, Splits, AutoSplit).

Сохраняются только сервисы из `place.json → Services`. Объекты из `Ignore` синхронизация не видит. Не добавляй сервисы, которых нет в `Scene/`.

## Формат
Одна строка — один объект:

    Класс "Имя" @src="..." #"Тег" Свойство=Значение $Атрибут=Значение {

Вложенные объекты пишутся между `{` и `}`. `{` стоит в конце строки объекта, `}` на отдельной строке. Отступы не важны. Объект без детей пишется без `{}`.

### Значения
- Имя объекта, теги, пути и строковые свойства — в двойных кавычках. Escape: \" \\ \n \r \t. Без кавычек строка допустима только если в ней нет пробелов, `"`, `{`, `}` и она не пустая; безопаснее всегда писать в кавычках.
- Без кавычек пишутся числа, true/false, Enum (только имя: `Material=Wood`), Vector3 `1,2,3`, Vector2 `1,2`, Color3 `#RRGGBB`, UDim2 `0.5,0,1,-40`, UDim `0.5,0`. Пробелов внутри таких значений нет.
- `true` пишется голым флагом: `Anchored`. `false` пишется только если дефолт true: `CanCollide=false`.
- Значения по умолчанию не пишутся. Чтобы вернуть дефолт — удали свойство.
- Числа — до 3 знаков после точки.
- Позиция и поворот детали — `CFrame=x,y,z` или `CFrame=x,y,z|rx,ry,rz` (повороты в градусах). Размер — `Size=x,y,z`.
- Если не уверен, как записывается свойство, найди такое же в существующих файлах `Scene/` и повтори стиль.

### Особые типы
- ColorSequence: `Color=0:#FF0000,0.5:#FFFF00,1:#0000FF` (время:цвет).
- NumberSequence: `Size=0:0.5,0.5:2,1:0` или с разбросом `время:значение:разброс`.
- Шрифт: `FontFace="GothamSSm|Bold|Normal"` (семейство|вес|стиль). Свойство `Font` не используй.
- BrickColor: `TeamColor="Bright blue"`.
- Грани и оси: `Faces=Top,Front`, `Axes=X,Z`.
- Физика: `CustomPhysicalProperties=плотность,трение,упругость,вес_трения,вес_упругости`.
- Vector3int16: `Vector3int16=1,2,3`.

### Атрибуты и теги
- Атрибуты: `$Health=100`, `$Name="Гоблин"`, `$Tint=#FF8800`. Поддерживаются boolean, number, string, Vector2, Vector3, Color3, UDim2. Остальные типы атрибутов не поддерживаются.
- Теги CollectionService: `#"Enemy"`.
- Атрибуты, начинающиеся с `_` (`$_id`, `$_geo`, `$_prefab`), служебные. Свои атрибуты с `_` не создавай.

## Пути и ссылки
- Путь объекта: имена от сервиса через `/`: `Workspace/Door/Frame`. У братьев с одинаковым именем второй — `Имя~2`. Символ `/` в имени пишется `%2F`, `%` — `%25`.
- Объект определяется путём: переименование = удаление + создание. Лишний раз не переименовывай.
- Ссылка на объект: `Part0=@"Workspace/Door/Frame"` либо через id.
- Id нужен, когда путь неудобен или может поменяться. Объекту ставят `$_id="frame1"`, ссылаются так: `Part0=@"*frame1"`. Id уникален в пределах плейса.
- Ссылка должна вести на существующий объект синхронизируемого сервиса. Битая ссылка, дубль id или ссылка на ignore-объект (например `Workspace/Camera`) останавливают весь Push с ошибкой.
- Ссылочные свойства: `Part0`, `Part1`, `PrimaryPart`, `Value` у ObjectValue и т.п. Атрибутами ссылки быть не могут.

## Скрипты
- В .bridge: `Script "Имя" @src="Scripts/Workspace/Door/Имя.lua"`. Код — в .lua, путь файла повторяет путь объекта. Классы: Script, LocalScript, ModuleScript.
- Новый скрипт = новый .lua + строка в .bridge.
- Короткий скрипт можно записать прямо в .bridge: `Script "Имя" @code="print(1)\nprint(2)"` или блоком (`>>>` на отдельной строке закрывает блок):

    Script "Имя" @code=<<<
        print("hi")
    >>>

  После Pull такой скрипт будет вынесен в `Scripts/*.lua`. Если есть и `@src`, и `@code`, побеждает `@src`.

## Вынос в файлы
Новый .bridge-файл подключай объектом без `{}` с `@file="Scene/.../Файл.bridge"`; файл содержит дочерние объекты этого объекта. Большие поддеревья приложение выносит само (порог `AutoSplit` в `place.json`).

## Префабы
- Префаб — файл `Prefabs/Lamp.bridge` с одним корневым объектом (с детьми).
- Экземпляр: объект с `$_prefab="Prefabs/Lamp.bridge"`. Положение и свойства экземпляра задаются на нём самом.
- Параметры — атрибуты корня префаба. В тексте префаба `"{Имя}"` подставляет значение параметра. Экземпляр переопределяет параметр своим атрибутом.
- Повороты префабов не поддерживаются: не задавай поворот экземпляру, если не уверен.
- Меняешь префаб — изменятся все экземпляры.

## Юнионы
- UnionOperation, NegateOperation, IntersectOperation хранят форму в `Geometry/<хеш>.bin`, в .bridge — только свойства и ссылка: `UnionOperation "Wall" Size=4,8,1 CFrame=0,4,0 Color=#888888 $_geo="a1b2c3d4e5f60718"`.
- Новую геометрию создать из файлов нельзя. Новый юнион делается только в Studio и потом через Pull.
- Можно: двигать, красить, менять свойства, копировать строку с тем же `$_geo` (получится ещё один такой же юнион), удалять.
- Нельзя: придумывать `$_geo` и править `.bin`. Несуществующий хеш = ошибка в preview, объект не создастся.
- Если подставить `$_geo` другого юниона, при Push форма заменится. Ссылки на этот юнион (например WeldConstraint) при замене сбиваются.

## Террейн
В `Scene/Workspace.bridge` у `Terrain` хранятся только свойства (вода, цвета и т.п.). Воксели лежат в `Terrain.voxels` и переносятся отдельными кнопками. Файл не трогай.

## Ограничения и ловушки
- Не выдумывай свойства и классы. Неизвестные игнорируются и показываются в preview.
- Сервисы (Workspace, Lighting, ...) создать или удалить нельзя, только менять их свойства и содержимое. Объекты, которые Studio создаёт сама (например `TouchInterest` в деталях инструмента), в файлах не нужны.
- У Part по умолчанию Size = 4,1.2,2 и серый цвет. У новых деталей всегда задавай `Size` и `Color` явно.
- Комментарии `//` допустимы, но при следующем Pull пропадут. Порядок объектов не важен: приложение сортирует.
- Отступы только пробелами, не табами.
- Не переносишь в Studio ничего вне синхронизируемых сервисов: объекты там помечаются «не синхронизируется».
- Один объект в файле — не больше ~500 КБ.

## Как проверить свою работу
Перед применением приложение показывает diff:
- `+` создастся, `-` удалится, `~` изменится,
- `x` будет проигнорировано (с причиной), `!` требует внимания (например, замена юниона).

Если в diff есть `-` или `x`, которых ты не планировал, остановись и разберись: скорее всего, ошибка в пути, имени класса или названии свойства. Массовые удаления (десятки объектов) — признак поломки файла.
""";
}