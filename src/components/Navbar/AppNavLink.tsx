import type { IconType } from "react-icons";
import { NavLink, useLocation, useNavigate } from "react-router-dom";
import type { Link } from "./Navbar";
import { Dropdown } from "../ui/Dropdown/Dropdown";


export const AppNavLink = (props: Link) => {
    const { path, label, className, subLinks } = props;
    const location = useLocation();
    const isActive = path === "/" ? location.pathname + location.search === path : (location.pathname + location.search).includes(path);

    return (
        <NavLink to={path} className={`nav-link ${isActive ? "nav-link-active" : ""} ${className}`}>
            <props.icon />
            <span>{label}</span>
        </NavLink>
    )
}
