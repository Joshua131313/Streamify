import type { IconType } from "react-icons";
import { NavLink, useLocation } from "react-router-dom";

interface Props {
    Icon: IconType; 
    path: string;
    label: string
}

export const AppNavLink = ({Icon, path, label}: Props) => {
    const location = useLocation();
    const isActive = path === "/" ? location.pathname + location.search === path : (location.pathname + location.search).includes(path);
    return (
        <NavLink to={path} className={`nav-link ${isActive ? "nav-link-active" : ""}`}>
            <Icon />
            <span>{label}</span>
        </NavLink>  
    )
}
