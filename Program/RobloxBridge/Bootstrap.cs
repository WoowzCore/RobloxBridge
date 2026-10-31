namespace RobloxBridge;

public static class Bootstrap{
    public static int Main(string[] Args){
        try{
            WL.Core.Start(Args);
            
            
        }catch(Exception e){
            WL.Logger.Fatal("Roblox взорвался...", e);
            
            return WL.Core.Stop(1);
        }

        return WL.Core.Stop(0);
    }
}