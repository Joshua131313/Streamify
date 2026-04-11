import { Outlet, useLocation, useNavigation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer/Footer"
import { Loader } from "../ui/Loader/Loader";
import { RouteProgress } from "../../router/RouteProgress";
import { Mobilebar } from "../Navbar/Mobilebar";
import { useScroll } from "../../hooks/utilHooks/useScroll";
import { SportsPlayer } from "../../pages/Sports/SportsPlayer";
import { useOnlineStatus } from "../../hooks/utilHooks/useOnlineStatus";
import { OfflineScreen } from "../ui/OfflineScreen/OfflineScreen";

interface Props {
    hideNav?: boolean;
    hideFooter?: boolean;
}

export const AppLayout = (props: Props) => {
    const { hideNav, hideFooter } = props;
    
    const isOnline = useOnlineStatus();

    useScroll();
    
    return (
        <>
            <RouteProgress />
            {!isOnline && <OfflineScreen />}
            {!hideNav && <Navbar />}
            <Mobilebar />

            <Outlet />
            <SportsPlayer />
            {!hideFooter && <Footer />}
        </>
    )
}