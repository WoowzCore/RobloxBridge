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

    public string Origin = "";                // «файл:строка» для сообщений об ошибках

    public BridgeProp? Get(string Key) => Props.Find(P => P.Key == Key);
}

public static class Bridge{
    public const int    FormatVersion = 1;
    public const string SceneDir      = "Scene";
    public const string ScriptsDir    = "Scripts";
    public const int    MapMaxPerLevel = 40;

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
            __ParseLine(Lines[I], I + 1, FileName, Roots, Open, Problems);
        }

        foreach(BridgeNode N in Open){
            Problems.Add($"{N.Origin}: не закрыта «{{» у {N.Class} \"{N.Name}\"");
        }

        return Roots;
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

    private sealed class WriteCtx{
        public Dictionary<string, string> Splits   = [];
        public Dictionary<string, string> Files    = [];                                   // относительный путь -> текст
        public HashSet<string>            Used     = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string>            Seen     = [];
        public List<string>               Warnings = [];
    }

    /// Раскладывает дерево по файлам и пишет в Scene/ и Scripts/ (только изменившиеся файлы, лишние удаляются).
    /// Splits дополняется автоматическими выносами — после вызова сохрани его в place.json.
    public static void WriteScene(string PlaceDir, List<BridgeNode> Roots, Dictionary<string, string> Splits, int AutoSplitLines, List<string> Warnings){
        string Root = Path.GetFullPath(PlaceDir);
        __SortTree(Roots);

        WriteCtx Ctx = new(){ Splits = Splits, Warnings = Warnings };
        __Measure(Roots, "", Splits, AutoSplitLines, true);

        string[] RootPaths = __SiblingPaths(Roots, "");
        string[] RootFiles = new string[Roots.Count];

        for(int I = 0; I < Roots.Count; I++){
            RootFiles[I] = __Unique(Ctx.Used, $"{SceneDir}/{__FileSeg(Roots[I].Name)}.bridge");
        }

        for(int I = 0; I < Roots.Count; I++){
            BridgeNode Clone = __Emit(Roots[I], RootPaths[I], Ctx);
            Ctx.Files[RootFiles[I]] = Write([Clone]);
        }

        foreach(string K in Splits.Keys){
            if(!Ctx.Seen.Contains(K)){ Warnings.Add($"Splits: объект «{K}» не найден (переименован или удалён?)"); }
        }

        foreach(var (Rel, Text) in Ctx.Files){
            string? Full = __Safe(Root, Rel);
            if(Full == null){ throw new Exception($"Недопустимый путь файла: {Rel}"); }

            __WriteIfChanged(Full, Text);
        }

        HashSet<string> Keep = new(Ctx.Files.Keys, StringComparer.OrdinalIgnoreCase);
        __Clean(Root, SceneDir,   ".bridge", Keep);
        __Clean(Root, ScriptsDir, ".lua",    Keep);
    }

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

    private static BridgeNode __Emit(BridgeNode N, string NodePath, WriteCtx Ctx){
        Ctx.Seen.Add(NodePath);

        BridgeNode C = new(){ Class = N.Class, Name = N.Name, Tags = N.Tags, Attrs = N.Attrs, Props = [..N.Props] };

        BridgeProp? Src = N.Get("Source");
        if(Src != null && Src.Kind == BridgeKind.Str){
            string Rel = __Unique(Ctx.Used, $"{ScriptsDir}/{__FileSegs(NodePath)}.lua");

            Ctx.Files[Rel] = Src.Value;
            C.Props.RemoveAll(P => P.Key == "Source");
            C.AtSrc = Rel;
        }

        List<BridgeNode> Kids  = [];
        string[]         Paths = __SiblingPaths(N.Children, NodePath);

        for(int I = 0; I < N.Children.Count; I++){ Kids.Add(__Emit(N.Children[I], Paths[I], Ctx)); }

        if(Ctx.Splits.TryGetValue(NodePath, out string? Target) && Kids.Count > 0){
            bool Ok = Target.StartsWith(SceneDir + "/", StringComparison.OrdinalIgnoreCase)
                   && Target.IndexOf('/', SceneDir.Length + 1) > 0
                   && Target.EndsWith(".bridge", StringComparison.OrdinalIgnoreCase);

            if(!Ok){
                Ctx.Warnings.Add($"Splits: «{Target}» для {NodePath} — файл должен лежать в подпапке Scene/ и иметь расширение .bridge. Использую стандартное имя.");
                Target = __DefaultFile(NodePath);
                Ctx.Splits[NodePath] = Target;
            }

            string Rel = __Unique(Ctx.Used, Target.Replace('\\', '/'));

            Ctx.Files[Rel] = Write(Kids);
            C.AtFile = Rel;
        }else{
            C.Children = Kids;
        }

        return C;
    }

    private static string __DefaultFile(string NodePath) => $"{SceneDir}/{__FileSegs(NodePath)}.bridge";

    private static string __FileSeg(string S){
        StringBuilder Sb = new();
        foreach(char C in S){ Sb.Append(Array.IndexOf(__BadChars, C) >= 0 ? '_' : C); }

        string R = Sb.ToString().TrimEnd('.', ' ');
        return R.Length == 0 ? "_" : R;
    }

    private static string __FileSegs(string NodePath) => string.Join('/', NodePath.Split('/').Select(__FileSeg));

    /// Гарантирует уникальное (без учёта регистра — Windows) имя файла: Name.ext, Name~2.ext...
    private static string __Unique(HashSet<string> Used, string Rel){
        string Ext  = Path.GetExtension(Rel);
        string Stem = Rel.Substring(0, Rel.Length - Ext.Length);
        string R    = Rel;
        int    K    = 2;

        while(!Used.Add(R)){ R = $"{Stem}~{K++}{Ext}"; }
        return R;
    }

    /// Полный путь внутри папки плейса или null, если путь выходит за её пределы.
    private static string? __Safe(string Root, string Rel){
        if(string.IsNullOrWhiteSpace(Rel) || Path.IsPathRooted(Rel)){ return null; }

        string Full   = Path.GetFullPath(Path.Combine(Root, Rel));
        string Prefix = Root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;

        return Full.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase) ? Full : null;
    }

    private static void __WriteIfChanged(string Full, string Text){
        Directory.CreateDirectory(Path.GetDirectoryName(Full)!);

        if(!File.Exists(Full) || File.ReadAllText(Full) != Text){
            File.WriteAllText(Full, Text, __Utf8);
        }
    }

    private static void __Clean(string Root, string Dir, string Ext, HashSet<string> Keep){
        string D = Path.Combine(Root, Dir);
        if(!Directory.Exists(D)){ return; }

        foreach(string F in Directory.EnumerateFiles(D, "*", SearchOption.AllDirectories)){
            if(!F.EndsWith(Ext, StringComparison.OrdinalIgnoreCase)){ continue; }

            string Rel = Path.GetRelativePath(Root, F).Replace('\\', '/');
            if(!Keep.Contains(Rel)){ File.Delete(F); }
        }

        foreach(string Sub in Directory.EnumerateDirectories(D, "*", SearchOption.AllDirectories).OrderByDescending(S => S.Length).ToList()){
            if(!Directory.EnumerateFileSystemEntries(Sub).Any()){ Directory.Delete(Sub); }
        }
    }

    // ======================================================================
    // Чтение сцены с диска

    /// Читает Scene/*.bridge (по файлу на сервис), подтягивает @file и @src. Ошибки и замечания — в Problems.
    public static List<BridgeNode> ReadScene(string PlaceDir, List<string> Problems){
        string Root  = Path.GetFullPath(PlaceDir);
        string Scene = Path.Combine(Root, SceneDir);

        List<BridgeNode> Roots   = [];
        HashSet<string>  Visited = new(StringComparer.OrdinalIgnoreCase);

        if(!Directory.Exists(Scene)){ return Roots; }

        foreach(string F in Directory.EnumerateFiles(Scene, "*.bridge", SearchOption.TopDirectoryOnly).OrderBy(F => F, StringComparer.OrdinalIgnoreCase)){
            string Rel = Path.GetRelativePath(Root, F).Replace('\\', '/');
            Visited.Add(Rel);

            List<BridgeNode> Part = Parse(File.ReadAllText(F), Rel, Problems);
            __Resolve(Part, Root, Visited, Problems);
            Roots.AddRange(Part);
        }

        foreach(string F in Directory.EnumerateFiles(Scene, "*.bridge", SearchOption.AllDirectories)){
            string Rel = Path.GetRelativePath(Root, F).Replace('\\', '/');
            if(!Visited.Contains(Rel)){ Problems.Add($"{Rel}: файл не подключён ни одним @file (будет удалён при следующем Pull)"); }
        }

        return Roots;
    }

    private static void __Resolve(List<BridgeNode> L, string Root, HashSet<string> Visited, List<string> Problems){
        foreach(BridgeNode N in L){
            if(N.AtSrc != null){
                string? Full = __Safe(Root, N.AtSrc);

                if(Full == null){            Problems.Add($"{N.Origin}: недопустимый путь @src \"{N.AtSrc}\""); }
                else if(!File.Exists(Full)){ Problems.Add($"{N.Origin}: файл @src не найден: {N.AtSrc}"); }
                else{
                    N.Props.RemoveAll(P => P.Key == "Source");
                    N.Props.Add(new BridgeProp("Source", File.ReadAllText(Full), BridgeKind.Str));
                }

                N.AtSrc = null;
            }

            __Resolve(N.Children, Root, Visited, Problems); // дети, написанные в скобках

            if(N.AtFile != null){
                string? Full = __Safe(Root, N.AtFile);

                if(Full == null){            Problems.Add($"{N.Origin}: недопустимый путь @file \"{N.AtFile}\""); }
                else if(!File.Exists(Full)){ Problems.Add($"{N.Origin}: файл @file не найден: {N.AtFile}"); }
                else if(!Visited.Add(Path.GetRelativePath(Root, Full).Replace('\\', '/'))){
                    Problems.Add($"{N.Origin}: файл {N.AtFile} подключён повторно (цикл или дубль)");
                }else{
                    if(N.Children.Count > 0){ Problems.Add($"{N.Origin}: у объекта и «{{ }}», и @file — оставьте одно"); }

                    List<BridgeNode> Kids = Parse(File.ReadAllText(Full), N.AtFile, Problems);
                    __Resolve(Kids, Root, Visited, Problems);
                    N.Children.AddRange(Kids);
                }

                N.AtFile = null;
            }
        }
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

    /// _map.txt всегда обновляется, AGENTS.md пишется, если его нет или он от другой версии формата.
    public static void WriteMeta(string PlaceDir, List<BridgeNode> Roots, Dictionary<string, string> Splits){
        __WriteIfChanged(Path.Combine(PlaceDir, "_map.txt"), Map(Roots, Splits));

        string Agents = Path.Combine(PlaceDir, "AGENTS.md");
        string Marker = $"<!-- bridge-format:{FormatVersion} -->";

        if(!File.Exists(Agents) || File.ReadLines(Agents).FirstOrDefault() != Marker){
            File.WriteAllText(Agents, Marker + "\n" + AgentsText, __Utf8);
        }
    }

    public const string AgentsText = """
# RobloxBridge: инструкция для ИИ

Эта папка — один плейс Roblox в текстовом формате .bridge. Приложение RobloxBridge переносит его в Studio и обратно кнопками Pull/Push. Git ведёт пользователь.

## Структура
- `Scene/<Сервис>.bridge` — по одному файлу на сервис (Workspace, Lighting, ...).
- `Scene/<Сервис>/...bridge` — вынесенные поддеревья, подключаются директивой `@file`.
- `Scripts/<путь объекта>.lua` — тексты скриптов, подключаются директивой `@src`.
- `_map.txt` — обзор дерева (не править). `place.json` — настройки (Services, Ignore, Splits).

## Формат
Одна строка — один объект:

    Класс "Имя" @src="..." #"Тег" Свойство=Значение $Атрибут=Значение {

Вложенные объекты пишутся между `{` и `}` (отступы не важны, `{` на той же строке, `}` на отдельной).

- Имя объекта, текст, пути и теги — всегда в двойных кавычках. Escape: \" \\ \n \r \t.
- Без кавычек: числа, true/false, Vector3 `1,2,3`, Color3 `#RRGGBB`, UDim2 `0.5,0,1,-40`, Enum (только имя) `Material=Wood`, CFrame `x,y,z` или `x,y,z|rx,ry,rz`. Пробелов в таких значениях нет.
- `true` пишется голым флагом: `Anchored`. Значения по умолчанию не пишутся; чтобы вернуть дефолт — удали свойство.
- У Part позиция — `Position` и `Orientation`, у Model — `Pivot`.
- Атрибуты: `$Health=100`. Теги: `#"Enemy"`.
- Ссылки на объекты: `Part0=@"Workspace/Door/Frame"` (имена от сервиса через `/`; у братьев с одинаковым именем второй — `Имя~2`).
- ID у объектов нет: объект определяется путём. Переименование = удаление + создание.
- Скрипт: в .bridge только `Script "Имя" @src="Scripts/.../Имя.lua"`, код — в .lua. Новый скрипт = новый .lua + строка в .bridge.
- Новый .bridge-файл подключай объектом без `{}` с `@file="Scene/.../Файл.bridge"`; файл содержит дочерние объекты.
- Комментарии `//` допустимы, но при следующем Pull пропадут. Порядок объектов не важен (приложение сортирует).

## Ограничения
- Не выдумывай свойства и классы: неизвестные будут проигнорированы и показаны в preview.
- Геометрия UnionOperation/NegateOperation и воксели Terrain в файлах не хранятся — такие объекты не трогай.
- Перед применением в Studio приложение показывает diff: что создастся, изменится, удалится, проигнорируется.
""";
}