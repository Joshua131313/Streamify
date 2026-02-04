import { Outlet, useLocation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer"

export const AppLayout = () => {
    const { pathname } = useLocation();
    const isMediaPage = pathname.startsWith("/movie") || pathname.startsWith("/tv");
    return (
        <>
            {!isMediaPage && <Navbar />}
            <Outlet />
            <Footer />
        </>
    )
}