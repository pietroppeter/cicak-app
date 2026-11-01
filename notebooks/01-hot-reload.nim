# Hot reloading basics
# The cells of the first proof of concept: each one is a module added to the
# running process. With hot reloading, a cell's top-level code runs once and
# the values of earlier variables survive. Add them in order.

# %% x
var x* = 41
echo "x = ", x

# %% y depends on x
var y* = x + 1
echo "y = x + 1 = ", y

# %% a proc
proc twice*(a: int): int = 2*a
echo "twice(y) = ", twice(y)

# %% change x
x = 100
echo "x = ", x, ", y is still ", y, ", twice(x) = ", twice(x)
