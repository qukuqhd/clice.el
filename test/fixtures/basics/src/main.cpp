#include "shapes.h"

#include <numeric>

#if __has_include(<vector>)
#include <vector>
#endif

int sum(const std::vector<int>& values) {
    return std::accumulate(values.begin(), values.end(), 0);
}

int main() {
    shapes::Circle c(2.0);
    shapes::Point a{0, 0};
    shapes::Point b{3, 4};
    double d = shapes::distance(a, b);
    std::vector<int> v{1, 2, 3};
    int total = sum(v);
    for (int i = 0; i < 3; ++i) {
        total += i;
    }
    if (total > 10) {
        total = 10;
    } else {
        total = 0;
    }
    return static_cast<int>(c.area() + d + total);
}
