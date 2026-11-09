using System.Runtime.InteropServices;

namespace RobloxBridge;

/// Нативный диалог выбора папки (IFileOpenDialog). Вызывать только из STA-потока.
public static class FolderDialog{
    private const uint FOS_PICKFOLDERS    = 0x00000020;
    private const uint FOS_FORCEFILESYSTEM = 0x00000040;
    private const uint FOS_PATHMUSTEXIST  = 0x00000800;
    private const uint SIGDN_FILESYSPATH  = 0x80058000;

    private const uint WS_POPUP         = 0x80000000;
    private const uint WS_EX_TOPMOST    = 0x00000008;
    private const uint WS_EX_TOOLWINDOW = 0x00000080;
    private const int  SW_SHOWNA        = 8;

    private const int HResultCancelled = unchecked((int)0x800704C7);

    /// Возвращает путь к папке или null, если пользователь отменил выбор.
    public static string? Pick(string Title){
        // Невидимое TopMost-окно-владелец, чтобы диалог не терялся за Studio
        IntPtr Owner = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, "STATIC", "", WS_POPUP,
                                       0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);

        if(Owner != IntPtr.Zero){
            ShowWindow(Owner, SW_SHOWNA);
            SetForegroundWindow(Owner);
        }

        try{
            IFileOpenDialog Dialog = (IFileOpenDialog)new FileOpenDialogCom();

            try{
                Dialog.GetOptions(out uint Options);
                Dialog.SetOptions(Options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
                Dialog.SetTitle(Title);

                int Hr = Dialog.Show(Owner);

                if(Hr == HResultCancelled){ return null; }
                Marshal.ThrowExceptionForHR(Hr);

                Dialog.GetResult(out IShellItem Item);

                try{
                    Item.GetDisplayName(SIGDN_FILESYSPATH, out IntPtr Ptr);

                    try{
                        return Marshal.PtrToStringUni(Ptr);
                    }finally{
                        Marshal.FreeCoTaskMem(Ptr);
                    }
                }finally{
                    Marshal.ReleaseComObject(Item);
                }
            }finally{
                Marshal.ReleaseComObject(Dialog);
            }
        }finally{
            if(Owner != IntPtr.Zero){ DestroyWindow(Owner); }
        }
    }

    // ----------------------------------------------------------------------
    // COM

    [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    private class FileOpenDialogCom{}

    // Порядок методов важен: это vtable. Ненужные методы объявлены как заглушки.
    [ComImport, Guid("D57C7288-D4AD-4768-BE02-9D969532D960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOpenDialog{
        [PreserveSig] int Show(IntPtr Owner);
        void SetFileTypes(uint Count, IntPtr Types);
        void SetFileTypeIndex(uint Index);
        void GetFileTypeIndex(out uint Index);
        void Advise(IntPtr Events, out uint Cookie);
        void Unadvise(uint Cookie);
        void SetOptions(uint Options);
        void GetOptions(out uint Options);
        void SetDefaultFolder(IShellItem Item);
        void SetFolder(IShellItem Item);
        void GetFolder(out IShellItem Item);
        void GetCurrentSelection(out IShellItem Item);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string Name);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string Name);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string Title);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string Text);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string Text);
        void GetResult(out IShellItem Item);
        void AddPlace(IShellItem Item, uint Placement);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string Extension);
        void Close(int Hr);
        void SetClientGuid(ref Guid Guid);
        void ClearClientData();
        void SetFilter(IntPtr Filter);
        void GetResults(out IntPtr Items);
        void GetSelectedItems(out IntPtr Items);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem{
        void BindToHandler(IntPtr Pbc, ref Guid Bhid, ref Guid Riid, out IntPtr Ppv);
        void GetParent(out IShellItem Item);
        void GetDisplayName(uint Sigdn, out IntPtr Name);
        void GetAttributes(uint Mask, out uint Attributes);
        void Compare(IShellItem Other, uint Hint, out int Order);
    }

    // ----------------------------------------------------------------------
    // user32

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(uint ExStyle, string ClassName, string? WindowName, uint Style,
                                                 int X, int Y, int Width, int Height,
                                                 IntPtr Parent, IntPtr Menu, IntPtr Instance, IntPtr Param);

    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr Hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr Hwnd, int Cmd);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr Hwnd);
}