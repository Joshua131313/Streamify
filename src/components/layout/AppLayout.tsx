import { Outlet, useLocation, useNavigation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer/Footer"
import { useScrollToTop } from "../../hooks/utilHooks/useScrollToTop";
import { Loader } from "../ui/Loader/Loader";
import { RouteProgress } from "../../router/RouteProgress";

interface Props {
    hideNav?: boolean;
    hideFooter?: boolean;
}

export const AppLayout = (props: Props) => {
    const { hideNav, hideFooter } = props;
                    ;

    useScrollToTop();
    
    return (
        <>
            <RouteProgress />

            {!hideNav && <Navbar />}
            <Outlet />
            {!hideFooter && <Footer />}
        </>
    )
}