import { createContext, useContext, useState } from "react";

type User = {
  id: string;
  email: string;
  token: string;
} | null;

type AppContextType = {
  user: User;
  setUser: (user: User) => void;

  loading: boolean;
  setLoading: (state: boolean) => void;

  theme: "light" | "dark";
  setTheme: (t: "light" | "dark") => void;
};

const AppContext = createContext<AppContextType | undefined>(undefined);

export const AppProvider = ({ children }: { children: React.ReactNode }) => {
  const [user, setUser] = useState<User>(null);
  const [loading, setLoading] = useState(false);
  const [theme, setTheme] = useState<"light" | "dark">("light");

  return (
    <AppContext.Provider
      value={{
        user,
        setUser,
        loading,
        setLoading,
        theme,
        setTheme,
      }}
    >
      {children}
    </AppContext.Provider>
  );
};

export const useApp = () => {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useApp must be used inside an AppProvider");
  return ctx;
};
