#include "shapes.h"

#include <cmath>

namespace shapes {

double Circle::area() const {
    return 3.14159 * radius * radius;
}

double distance(const Point& a, const Point& b) {
    double dx = a.x - b.x;
    double dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

}
