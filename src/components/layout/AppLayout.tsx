import { Outlet, useLocation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer"
import { useScrollToTop } from "../../hooks/utilHooks/useScrollToTop";

export const AppLayout = () => {
    const { pathname } = useLocation();
    const isMediaPage = pathname.startsWith("/movie") || pathname.startsWith("/tv");
    
    useScrollToTop();
    
    return (
        <>
            {!isMediaPage && <Navbar />}
            <Outlet />
            <Footer />
        </>
    )
}