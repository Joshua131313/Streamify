import { createContext, useContext, useEffect, useState } from "react";
import { darkThemeColors, lightThemeColors } from "../data/theme";
import { useLocation } from "react-router-dom";
import { navLinks } from "../components/Navbar/Navbar";
import { useIsTouchDevice } from "../hooks/utilHooks/isMobile";

type Theme = "light" | "dark";

type AppContextType = {
  theme: Theme;
  setTheme: (t: Theme) => void;
  toggleTheme: () => void;
  lastMainRoute: string;
  setLastMainRoute: (route: string) => void;
  isMobile: boolean;
};

export const AppContext = createContext<AppContextType | undefined>(undefined);

export const AppProvider = ({ children }: { children: React.ReactNode }) => {

  const getSystemTheme = (): Theme => {
    return window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  };
  const [lastMainRoute, setLastMainRoute] = useState("/");
  const [theme, setTheme] = useState<Theme>(getSystemTheme);
  const location = useLocation();
  const isMobile = useIsTouchDevice();

  const toggleTheme = () => {
    setTheme(prev => (prev === "dark" ? "light" : "dark"));
  };

const mainPaths = ["/", "/discover", "/sports", "/search", "/saved-media", "/history"];

useEffect(() => {
  const isMainRoute = mainPaths.some(path => {
    if (path === "/sports") {
      return location.pathname.startsWith("/sports"); 
    }
    return location.pathname === path;
  });

  if (isMainRoute) {

    const search = location.search.includes("provider") ? "" : location.search;

    setLastMainRoute(location.pathname + search);
  }
}, [location]);

  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");

    const handleChange = (e: MediaQueryListEvent) => {
      setTheme(e.matches ? "dark" : "light");
    };

    media.addEventListener("change", handleChange);

    return () => {
      media.removeEventListener("change", handleChange);
    };
  }, []);

  useEffect(() => {
    const palette = theme === "dark" ? darkThemeColors : lightThemeColors;

    document.body.classList.toggle("dark", theme === "dark");
    document.body.classList.toggle("light", theme === "light");

    Object.entries(palette).forEach(([key, value]) => {
      document.documentElement.style.setProperty(key, value);
    });
  }, [theme]);

  return (
    <AppContext.Provider value={{
      theme,
      setTheme,
      toggleTheme,
      lastMainRoute,
      setLastMainRoute,
      isMobile
    }}>
      {children}
    </AppContext.Provider>
  );
};

export const useApp = () => {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useApp must be used inside an AppProvider");
  return ctx;
};