import { Logo } from "../ui/Logo/Logo"
import { Container } from "../layout/Container/Container"
import "./Navbar.css"
import { FaFilm, FaHome, FaSearch, FaSquarespace, FaTv } from "react-icons/fa"
import { FaCubesStacked } from "react-icons/fa6"
import { Link } from "react-router-dom"
import { Mobilebar } from "./Mobilebar"

export const NavLinks = () => {
    return (
        <div className="nav-links">
            <Link to={"/"} className="nav-link">
                <FaHome />
                <span>Home</span>
            </Link>
            <Link to="/discover?media=movie" className="nav-link">
                <FaFilm />
                <span>Movies</span>
            </Link>
            <Link to="/discover?media=tv" className="nav-link">
                <FaTv />
                <span>TV Shows</span>
            </Link>
            <Link to={"/search"} className="nav-link search-link">
                <FaSearch />
                <span>Search</span>
            </Link>
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