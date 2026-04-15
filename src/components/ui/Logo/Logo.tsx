import { Link } from "react-router-dom"
import "./Logo.css"
import { AppImg } from "../ImgProxy/AppImg"

export const Logo = () => {

    return (
        <Link to={"/"}  className="logo">
            <AppImg 
                src="/logo/streamify-logo.png"
            />
            {/* Streamify */}
        </Link>
    )
}