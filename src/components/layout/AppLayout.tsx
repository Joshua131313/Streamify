import { Outlet, useLocation, useNavigation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer/Footer"
import { RouteProgress } from "../../router/RouteProgress";
import { Mobilebar } from "../Navbar/Mobilebar";
import { useScroll } from "../../hooks/utilHooks/useScroll";
import { SportsPlayer } from "../../pages/Sports/SportsPlayer";
import { NetworkIndicatorScreen } from "../ui/NetworkIndicatorScreen/NetworkIndicatorScreen";
import { Loader } from "../ui/Loader/Loader";
import { SportsSidebar } from "../sports/SportsSidebar/SportsSidebar";
import { useApp } from "../../context/AppContext";
import { useEffect } from "react";

interface Props {
    hideNav?: boolean;
    hideFooter?: boolean;
}

export const AppLayout = (props: Props) => {
    const { hideNav, hideFooter } = props;
    const { lastMainRoute, setLastMainRoute } = useApp()
    const location = useLocation();
    useScroll();
    useEffect(() => {
        const path = location.pathname;
        console.log("lastMainRoute", lastMainRoute)
        if (path === "/") {
            setLastMainRoute("/");
        } else if (path.startsWith("/sports")) {
            setLastMainRoute("/sports");
        } else if (path.startsWith("/search")) {
            setLastMainRoute("/search");
        }
        else if (path.startsWith("discover")) {
            setLastMainRoute("/discover")
        }
    }, [location.pathname]);
    return (
        <>

            <RouteProgress />
            <NetworkIndicatorScreen />
            {!hideNav && <Navbar />}
            <Mobilebar />

            <Outlet />
            <SportsPlayer />
            {location.pathname.includes("sports") && <SportsSidebar />}
            {!hideFooter && <Footer />}
        </>
    )
}