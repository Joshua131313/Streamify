import { Logo } from "../ui/Logo/Logo"
import { Container } from "../layout/Container/Container"
import "./Navbar.css"
import { FaFilm, FaHockeyPuck, FaHome, FaSearch, FaSquarespace, FaTv } from "react-icons/fa"
import { FaBaseball, FaBasketball, FaClapperboard, FaCubesStacked, FaHouse } from "react-icons/fa6"
import { NavLink, useLocation } from "react-router-dom"
import { Mobilebar } from "./Mobilebar"
import type { IconType } from "react-icons"
import { AppNavLink } from "./AppNavLink"
import { BsBookmarkFill } from "react-icons/bs"
import { UserIcon } from "../ui/User/UserIcon"
import { useEffect, useState } from "react"

export interface Link {
    path: string,
    icon: IconType,
    label: string,
    className?: string,
    subLinks?: Link[]
}

export const navLinks: Link[] = [
    {
        path: "/",
        icon: FaHouse,
        label: "Discover",
    },
    {
        path: "/discover?media=movie",
        icon: FaClapperboard,
        label: "Movies",
    },
    {
        path: "/discover?media=tv",
        icon: FaTv,
        label: "Shows",
    },
    {
        path: "/sports",
        icon: FaBasketball,
        label: "Sports",
        subLinks: [
            {
                icon: FaBasketball,
                label: "NBA",
                path: "/sports/nba",
            },
            {
                icon: FaHockeyPuck,
                label: "NHL",
                path: "/sports/nhl"
            },
            {
                icon: FaBaseball,
                label: "MLB",
                path: "/sports/mlb"
            }
        ]
    },
    {
        path: "/search",
        icon: FaSearch,
        label: "Search",
    },

]

export const NavLinks = () => {
    return (
        <div className="nav-links">
            {navLinks.map(link => {
                return <AppNavLink {...link} key={link.path} />
            })}
        </div>
    )
}

export const Navbar = () => {

    const location = useLocation();
    const activeLink = navLinks.find(link => {
        if (link.path === "/") {
            return location.pathname === "/";
        }

        return location.pathname.startsWith(link.path);
    });
    const subLinks = activeLink?.subLinks;

    return (
        <>
            <Container className={`navbar`}>
                <Logo />
                <NavLinks />
                <UserIcon />
            </Container>
            {subLinks && subLinks.length > 0 && (
                <Container className="navbar sub-nav">
                    <div className="nav-links">
                        {subLinks.map(link => (
                            <AppNavLink {...link} key={link.path} />
                        ))}
                    </div>
                </Container>
            )}
        </>
    );
};