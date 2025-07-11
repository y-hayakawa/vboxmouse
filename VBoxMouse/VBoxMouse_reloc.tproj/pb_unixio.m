
#import <sys/errno.h>
#import <sys/types.h>
#import <sys/buf.h>
#import <sys/conf.h>
#import <sys/uio.h>
#import <sys/mtio.h>

#import <driverkit/align.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/return.h>
#import <driverkit/devsw.h>
#import <kernserv/prototypes.h>
#import <machkit/NXLock.h>

#import "VBoxMouse.h"

extern struct pb_data pbData ;

#undef DEBUG

int pb_open(dev_t dev, int flag, int devtype, struct proc *pp)
{
    return 0 ;
}

int pb_close(dev_t dev, int flag, int mode, struct proc *p) 
{
    return 0 ;
}

// read VBox PB data and copy to NS
int pb_read(dev_t dev, struct uio *uiop, int ioflag)
{
    int ret,len_copy ;
    if(uiop->uio_iovcnt != 1)  return(EINVAL) ;
    if(uiop->uio_iov->iov_len == 0) return 0 ;   
    if (pbData.pb_read_buffer_len==0) return 0 ;
    [pbData.lock lock] ;
    len_copy = MIN(pbData.pb_read_buffer_len, uiop->uio_iov->iov_len) ;
    ret = copyout(pbData.pb_read_buffer, uiop->uio_iov->iov_base, len_copy);
#ifdef DEBUG
    IOLog("pb_read: ret=%d len_copy=%d\n",ret,len_copy) ;
#endif
    uiop->uio_iov->iov_base = (char *)uiop->uio_iov->iov_base + len_copy;
    uiop->uio_iov->iov_len -= len_copy;
    uiop->uio_resid -= len_copy ;
    [pbData.lock unlock] ;
    return ret ;
}

// read data from NS and store to write buffer
int pb_write(dev_t dev, struct uio *uiop, int ioflag) 
{
    int ret,len_copy ;
    if(uiop->uio_iovcnt != 1)  return(EINVAL) ;
    if(uiop->uio_iov->iov_len == 0) return 0 ;   

    [pbData.lock lock] ;
    len_copy = MIN(uiop->uio_iov->iov_len, MAX_BUFFER_LEN) ;
    ret = copyin(uiop->uio_iov->iov_base, pbData.pb_write_buffer, len_copy) ;
#ifdef DEBUG
    IOLog("pb_write: ret=%d len_copy=%d\n",ret,len_copy) ;
#endif
    pbData.pb_write_buffer_len = len_copy ;
    uiop->uio_iov->iov_base = (char *)uiop->uio_iov->iov_base + len_copy;
    uiop->uio_iov->iov_len -= len_copy;
    uiop->uio_resid -= len_copy ;
    pbData.pb_got_new_data_to_write = len_copy ;
    [pbData.lock unlock] ;
    return ret ;
}



