import type { IconType } from "react-icons";
import { NavLink, useLocation, useNavigate } from "react-router-dom";
import type { Link } from "./Navbar";
import { Dropdown } from "../ui/Dropdown/Dropdown";


export const AppNavLink = (props: Link) => {
    const {path, label, className, subLinks} = props;
    const location = useLocation();
    const isActive = path === "/" ? location.pathname + location.search === path : (location.pathname + location.search).includes(path);
    const navigate = useNavigate();
    const LinkComponent = () => (
        <NavLink to={path} className={`nav-link ${isActive ? "nav-link-active" : ""} ${className}`}>
            <props.icon />
            <span>{label}</span>
        </NavLink>  
    )

    if(subLinks) {
        return (
            <Dropdown
                dropdownOptions={subLinks.map(link => ({
                    value: link.label,
                    icon: link.icon,
                    onClick: () => navigate(link.path),
                    key: link.label
                }))}
                title="Sports"
            >
                <LinkComponent />
            </Dropdown>
        )
    }
    
    return <LinkComponent />
}
