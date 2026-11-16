#pragma once

#include <string>

namespace shapes {

struct Point {
    int x;
    int y;
};

class Shape {
public:
    virtual ~Shape() = default;
    virtual double area() const = 0;
    virtual std::string name() const { return "shape"; }
};

class Circle : public Shape {
public:
    explicit Circle(double r) : radius(r) {}
    double area() const override;
    std::string name() const override { return "circle"; }

    double radius;
};

double distance(const Point& a, const Point& b);

}
