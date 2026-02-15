import { Logo } from "../ui/Logo/Logo"
import { Container } from "../layout/Container/Container"
import "./Navbar.css"
import { FaFilm, FaHome, FaSearch, FaSquarespace, FaTv } from "react-icons/fa"
import { FaCubesStacked } from "react-icons/fa6"
import { NavLink } from "react-router-dom"
import { Mobilebar } from "./Mobilebar"
import type { IconType } from "react-icons"
import { AppNavLink } from "./AppNavLink"
import { BsBookmarkFill } from "react-icons/bs"

const navLinks : {path: string, Icon: IconType, label: string}[] = [
    {
        path: "/",
        Icon: FaHome,
        label: "Discover"
    },
    {
        path: "/discover?media=movie",
        Icon: FaFilm,
        label: "Movies"
    },
    {
        path: "/discover?media=tv",
        Icon: FaTv,
        label: "Shows"
    },
    {
        path: "/saved",
        Icon: BsBookmarkFill,
        label: "Saved"
    },
    {
        path: "/search",
        Icon: FaSearch,
        label: "Search"
    },

]

export const NavLinks = () => {
    return (
        <div className="nav-links">
            {navLinks.map(link => {
                return <AppNavLink {...link} key={link.path}/>
            })}
        </div>
    )
}
export const Navbar = ()  => {

    return (
        <>
        <Container className="navbar">
            <Logo />
            <NavLinks />
        </Container>
        <Mobilebar />
        </>
    )
}