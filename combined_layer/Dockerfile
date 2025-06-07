# FROM amazonlinux:2
# RUN yum update -y && yum install -y gcc openssl-devel bzip2-devel libffi-devel zlib-devel wget make tar gzip libgfortran blas lapack zip xz-devel && yum clean all
# RUN wget https://www.python.org/ftp/python/3.9.6/Python-3.9.6.tgz && tar xzf Python-3.9.6.tgz && cd Python-3.9.6 && ./configure --enable-optimizations --with-lzma && make -j$(nproc) && make install && cd .. && rm -rf Python-3.9.6 Python-3.9.6.tgz
# RUN /usr/local/bin/python3.9 --version
# RUN mkdir -p /python
# RUN /usr/local/bin/pip3.9 install numpy==1.21.6 pandas==1.3.5 -t /python --verbose && ls -l /python
# RUN /usr/local/bin/python3.9 -c "import sys; sys.path.append('/python'); import numpy; print('NumPy version:', numpy.__version__); import numpy.core._multiarray_umath; import pandas; print('Pandas version:', pandas.__version__); print('Success')"
# RUN cd / && zip -r /tmp/combined_layer.zip python && ls -l /tmp/combined_layer.zip
# CMD ["cp", "/tmp/combined_layer.zip", "/output"]

FROM amazonlinux:2


RUN yum update -y && yum install -y gcc gcc-gfortran openssl-devel bzip2-devel libffi-devel zlib-devel wget make tar gzip libgfortran blas lapack openblas atlas libopenblas-dev zip xz-devel && yum clean all

RUN wget https://www.python.org/ftp/python/3.9.6/Python-3.9.6.tgz && tar xzf Python-3.9.6.tgz && cd Python-3.9.6 && ./configure --enable-optimizations --with-lzma && make -j$(nproc) && make install && cd .. && rm -rf Python-3.9.6 Python-3.9.6.tgz
RUN /usr/local/bin/python3.9 --version
RUN mkdir -p /python
RUN /usr/local/bin/pip3.9 install numpy==1.21.6 --no-binary numpy -t /python --no-cache-dir --verbose && /usr/local/bin/pip3.9 install pandas==1.3.5 -t /python --no-cache-dir --verbose && ls -l /python
RUN /usr/local/bin/python3.9 -c "import sys; sys.path.append('/python'); import numpy; print('NumPy version:', numpy.__version__); import numpy.core._multiarray_umath; print('Multiarray umath OK'); import pandas; print('Pandas version:', pandas.__version__); print('Success')"
RUN ls -l /python/numpy/core/_multiarray_umath*.so
RUN cd / && zip -r /tmp/combined_layer.zip python && ls -l /tmp/combined_layer.zip
CMD ["cp", "/tmp/combined_layer.zip", "/output"]