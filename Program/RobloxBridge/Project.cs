using System.Text.Json;

namespace RobloxBridge;

public sealed record PlaceInfo(long PlaceId, long UniverseId, string? PlaceName, string? RobloxVersion);

public sealed class ProjectData{
    public int     Format        { get; set; } = Project.FormatVersion;
    public string  Name          { get; set; } = "";
    public long    PlaceId       { get; set; }
    public long    UniverseId    { get; set; }
    public string? PlaceName     { get; set; }
    public string? RobloxVersion { get; set; }
    public string? LastPull      { get; set; }
}

public sealed record ProjectHandle(string Dir, ProjectData Data);

public static class Project{
    public const string MarkerFile    = "bridge.json";
    public const int    FormatVersion = 1;

    private static readonly JsonSerializerOptions __Json = new(){ WriteIndented = true, PropertyNameCaseInsensitive = true };

    public static volatile ProjectHandle? Current = null;

    public static bool IsOpen => Current != null;

    public static bool TryOpen(string Folder, out string Error){
        Error = "";

        try{
            string Full   = Path.GetFullPath(Folder);
            string Marker = Path.Combine(Full, MarkerFile);

            if(!File.Exists(Marker)){
                Error = $"В папке нет {MarkerFile}, это не проект RobloxBridge.\nНовый проект создаётся из плагина в Roblox Studio.";
                return false;
            }

            ProjectData? Data = JsonSerializer.Deserialize<ProjectData>(File.ReadAllText(Marker), __Json);

            if(Data == null){
                Error = $"Файл {MarkerFile} пуст или повреждён.";
                return false;
            }

            if(Data.Format > FormatVersion){
                Error = $"Проект создан более новой версией RobloxBridge (формат {Data.Format}, поддерживается {FormatVersion}).";
                return false;
            }

            if(string.IsNullOrWhiteSpace(Data.Name)){
                Data.Name = new DirectoryInfo(Full).Name;
            }

            Current = new ProjectHandle(Full, Data);
            return true;
        }catch(Exception e){
            Error = $"Не удалось прочитать проект: {e.Message}";
            return false;
        }
    }

    public static bool TryCreate(string Folder, PlaceInfo Info, out string Error){
        Error = "";

        try{
            string Full   = Path.GetFullPath(Folder);
            string Marker = Path.Combine(Full, MarkerFile);

            if(File.Exists(Marker)){
                Error = "В этой папке уже есть проект RobloxBridge.\nОткройте его кнопкой «Открыть проект» в приложении.";
                return false;
            }

            ProjectData Data = new(){
                Name          = new DirectoryInfo(Full).Name,
                PlaceId       = Info.PlaceId,
                UniverseId    = Info.UniverseId,
                PlaceName     = Info.PlaceName,
                RobloxVersion = Info.RobloxVersion
            };

            File.WriteAllText(Marker, JsonSerializer.Serialize(Data, __Json));

            Current = new ProjectHandle(Full, Data);
            return true;
        }catch(Exception e){
            Error = $"Не удалось создать проект: {e.Message}";
            return false;
        }
    }

    public static void Close(){
        Current = null;
    }

    public static string CheckPlace(long PlaceId, long UniverseId){
        ProjectData? Data = Current?.Data;

        if(Data == null)                                            { return "none"; }
        if(PlaceId == 0)                                            { return "local"; }
        if(Data.PlaceId == 0)                                       { return "unbound"; }
        if(Data.PlaceId == PlaceId)                                 { return "match"; }
        if(UniverseId != 0 && Data.UniverseId == UniverseId)        { return "sameGame"; }

        return "other";
    }
}