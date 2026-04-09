import { Outlet } from "react-router-dom";
import { ErrorBoundary } from "../components/ui/Error/ErrorBoundary";
import { AuthProvider } from "../context/AuthContext";
import { HelmetProvider } from "react-helmet-async";
import { AppProvider } from "../context/AppContext";
import { ContextMenuProvider } from "../context/ContextMenu";
import { WindowManagerProvider } from "../context/WindowManagerContext";
import { MultiWatchProvider } from "../context/MultiWatchContext";
import { SportsProvider } from "../context/SportsContext";
import { WindowRenderer } from "../components/ui/Window/WindowRenderer";
import { SavedMediaProvider } from "../context/SavedMediaContext";
import { SearchHistoryProvider } from "../context/SearchHistoryContext";
import { FavoriteTeamsProvider } from "../context/FavoriteTeamsContext";
import { WatchHistoryProvider } from "../context/WatchHistoryContext";

const DataProviders = ({ children }: { children: React.ReactNode }) => {
  return (
    <SavedMediaProvider>
      <SearchHistoryProvider>
        <FavoriteTeamsProvider>
          <WatchHistoryProvider>
            {children}
          </WatchHistoryProvider>
        </FavoriteTeamsProvider>
      </SearchHistoryProvider>
    </SavedMediaProvider>
  );
};

export const RootLayout = () => {
  return (
    <ErrorBoundary>
      <AuthProvider>
        <HelmetProvider>
          <AppProvider>
            <DataProviders>
              <ContextMenuProvider>
                <WindowManagerProvider>
                  <MultiWatchProvider>
                    <SportsProvider>
                      <WindowRenderer />
                      <div className="body">
                        <Outlet />
                      </div>
                    </SportsProvider>
                  </MultiWatchProvider>
                </WindowManagerProvider>
              </ContextMenuProvider>
            </DataProviders>
          </AppProvider>
        </HelmetProvider>
      </AuthProvider>
    </ErrorBoundary>
  );
};