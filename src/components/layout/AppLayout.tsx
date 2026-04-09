import { Outlet, useLocation, useNavigation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer/Footer"
import { Loader } from "../ui/Loader/Loader";
import { RouteProgress } from "../../router/RouteProgress";
import { Mobilebar } from "../Navbar/Mobilebar";
import { useScroll } from "../../hooks/utilHooks/useScroll";

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

            {!hideNav && <Navbar />}
            <Mobilebar />

            <Outlet />
            {!hideFooter && <Footer />}
        </>
    )
}