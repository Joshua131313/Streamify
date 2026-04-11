import { Outlet, useLocation, useNavigation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer/Footer"
import { RouteProgress } from "../../router/RouteProgress";
import { Mobilebar } from "../Navbar/Mobilebar";
import { useScroll } from "../../hooks/utilHooks/useScroll";
import { SportsPlayer } from "../../pages/Sports/SportsPlayer";
import { NetworkIndicatorScreen } from "../ui/NetworkIndicatorScreen/NetworkIndicatorScreen";
import { Loader } from "../ui/Loader/Loader";

interface Props {
    hideNav?: boolean;
    hideFooter?: boolean;
}

export const AppLayout = (props: Props) => {
    const { hideNav, hideFooter } = props;
    
    useScroll();
    
    return (
        <>
            <RouteProgress />
            <NetworkIndicatorScreen />
            {!hideNav && <Navbar />}
            <Mobilebar />

            <Outlet />
            <SportsPlayer />
            {!hideFooter && <Footer />}
        </>
    )
}