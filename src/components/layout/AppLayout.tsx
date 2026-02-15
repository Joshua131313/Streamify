import { Outlet, useLocation, useNavigation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer/Footer"
import { useScrollToTop } from "../../hooks/utilHooks/useScrollToTop";
import { Loader } from "../ui/Loader/Loader";

export const AppLayout = () => {
    const { pathname } = useLocation();
    const isMediaPage = pathname.startsWith("/movie") || pathname.startsWith("/tv");
    const navigation = useNavigation();

    useScrollToTop();
    
    return (
        <>
            {navigation.state === "loading" && <div className="loading-indicator">loading</div>}
            {!isMediaPage && <Navbar />}
            <Outlet />
            <Footer />
        </>
    )
}