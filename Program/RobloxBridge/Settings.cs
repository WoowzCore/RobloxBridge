using System.Text.Json;

namespace RobloxBridge;

public static class Settings{
    private sealed class Data{
        public int     Port        { get; set; } = 4949;
        public string? LastProject { get; set; }
    }

    private static readonly string __File = Path.Combine(AppContext.BaseDirectory, "robloxbridge.settings.json");
    private static          Data   __Data = new();

    public static int Port{
        get => __Data.Port;
        set{ __Data.Port = value; __Save(); }
    }

    public static string? LastProject{
        get => __Data.LastProject;
        set{ __Data.LastProject = value; __Save(); }
    }

    public static void Load(){
        try{
            if(!File.Exists(__File)){ return; }

            Data? Loaded = JsonSerializer.Deserialize<Data>(File.ReadAllText(__File));
            if(Loaded == null){ return; }

            if(Loaded.Port is < 1 or > 65535){ Loaded.Port = 4949; }
            __Data = Loaded;
        }catch(Exception e){
            WL.Logger.Warn("Не удалось загрузить настройки.", e);
        }
    }

    private static void __Save(){
        try{
            File.WriteAllText(__File, JsonSerializer.Serialize(__Data, new JsonSerializerOptions{ WriteIndented = true }));
        }catch(Exception e){
            WL.Logger.Warn("Не удалось сохранить настройки.", e);
        }
    }
}