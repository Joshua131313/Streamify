import { Logo } from "../ui/Logo/Logo"
import { Container } from "../layout/Container/Container"
import "./Navbar.css"
import { FaFilm, FaHome, FaSearch, FaSquarespace, FaTv } from "react-icons/fa"
import { FaBasketball, FaCubesStacked } from "react-icons/fa6"
import { NavLink } from "react-router-dom"
import { Mobilebar } from "./Mobilebar"
import type { IconType } from "react-icons"
import { AppNavLink } from "./AppNavLink"
import { BsBookmarkFill } from "react-icons/bs"
import { UserIcon } from "../ui/User/UserIcon"

const navLinks : {path: string, Icon: IconType, label: string, className: string}[] = [
    {
        path: "/",
        Icon: FaHome,
        label: "Discover",
        className: ""
    },
    {
        path: "/discover?media=movie",
        Icon: FaFilm,
        label: "Movies",
        className: ""
    },
    {
        path: "/discover?media=tv",
        Icon: FaTv,
        label: "Shows",
        className: ""
    },
    {
        path: "/sports",
        Icon: FaBasketball,
        label: "Sports",
        className: ""
    },
    {
        path: "/search",
        Icon: FaSearch,
        label: "Search",
        className: ""
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
            {/* only shown in mobile navbar */}
            <UserIcon />
        </Container>
        </>
    )
}